const admin = require('firebase-admin');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { logger } = require('firebase-functions');
const { SpeechClient } = require('@google-cloud/speech');

admin.initializeApp();
const speechClient = new SpeechClient();

exports.transcribeEmergencyAudio = onCall(
  {
    cors: true,
    timeoutSeconds: 60,
    maxInstances: 10,
  },
  async (request) => {
    const audioBase64 = String(request.data?.audioBase64 || '').trim();
    const languageCode = String(request.data?.languageCode || 'en-IN').trim();
    const alternativeLanguageCodes = Array.isArray(request.data?.alternativeLanguageCodes)
      ? request.data.alternativeLanguageCodes
          .map((code) => String(code || '').trim())
          .filter((code) => code)
      : [];

    if (!audioBase64) {
      throw new HttpsError('invalid-argument', 'audioBase64 is required.');
    }

    try {
      const [response] = await speechClient.recognize({
        config: {
          encoding: 'LINEAR16',
          sampleRateHertz: 16000,
          languageCode,
          alternativeLanguageCodes,
          enableAutomaticPunctuation: true,
          model: 'latest_long',
        },
        audio: {
          content: audioBase64,
        },
      });

      const alternatives = (response.results || [])
        .map((result) => result.alternatives && result.alternatives[0])
        .filter(Boolean);

      const transcript = alternatives
        .map((alt) => alt.transcript || '')
        .join(' ')
        .trim();

      let confidence = 0;
      if (alternatives.length > 0) {
        const total = alternatives
          .map((alt) => Number(alt.confidence || 0))
          .reduce((sum, value) => sum + value, 0);
        confidence = total / alternatives.length;
      }

      return {
        transcript,
        confidence,
      };
    } catch (error) {
      logger.error('Cloud transcription failed', {
        message: error?.message,
      });
      throw new HttpsError('internal', 'Cloud transcription failed.');
    }
  }
);

const INCIDENT_TOPIC_RULES = [
  {
    match: /(medical|injury|bleeding|insulin|faint|fall)/i,
    topics: ['responder_general', 'responder_medical_emergency', 'responder_off_duty_authority'],
  },
  {
    match: /(fire|smoke|burn)/i,
    topics: ['responder_general', 'responder_fire_and_rescue', 'responder_off_duty_authority'],
  },
  {
    match: /(flood|storm|earthquake|evacuation|shelter)/i,
    topics: [
      'responder_general',
      'responder_shelter_and_evacuation',
      'responder_logistics_and_transport',
      'responder_civil_defense',
      'responder_off_duty_authority',
    ],
  },
  {
    match: /(women|harassment|woman safety)/i,
    topics: ['responder_general', 'responder_women_safety', 'responder_police', 'responder_off_duty_authority'],
  },
  {
    match: /(child|kid|missing)/i,
    topics: ['responder_general', 'responder_child_safety', 'responder_search_and_rescue', 'responder_police'],
  },
  {
    match: /(food|water|medicine|suppl)/i,
    topics: ['responder_general', 'responder_food_and_water_supply', 'responder_essential_medicines', 'responder_logistics_and_transport'],
  },
];

function normalizeTopic(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/&/g, 'and')
    .replace(/[^a-z0-9_]/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_|_$/g, '');
}

function topicsForRequest(requestData) {
  const topics = new Set(['responder_general', 'responder_off_duty_authority']);

  const category = String(requestData.category || '');
  const summary = String(requestData.summary || '');
  const recommendedSkill = String(requestData.recommendedSkill || '');
  const haystack = `${category} ${summary} ${recommendedSkill}`;

  for (const rule of INCIDENT_TOPIC_RULES) {
    if (rule.match.test(haystack)) {
      rule.topics.forEach((topic) => topics.add(topic));
    }
  }

  const normalizedSkill = normalizeTopic(recommendedSkill);
  if (normalizedSkill) {
    topics.add(`responder_${normalizedSkill}`);
  }

  return Array.from(topics);
}

async function sendTopicAlert(topic, requestData) {
  const title = `New SOS: ${requestData.category || 'Emergency'}`;
  const rawMessage = String(requestData.originalMessage || '').trim();
  const body = rawMessage
    ? `${rawMessage} (${requestData.severity || 'medium'})`
    : `${requestData.summary || 'Emergency request received.'} (${requestData.severity || 'medium'})`;

  await admin.messaging().send({
    topic,
    notification: {
      title,
      body,
    },
    data: {
      requestId: String(requestData.id || ''),
      requestCategory: String(requestData.category || ''),
      severity: String(requestData.severity || ''),
      recommendedSkill: String(requestData.recommendedSkill || ''),
      originalMessage: String(requestData.originalMessage || ''),
      voiceTranscript: String(requestData.voiceTranscript || ''),
      voiceAudioUrl: String(requestData.voiceAudioUrl || ''),
      voiceAudioType: String(requestData.voiceAudioType || ''),
      attachmentUrl: String(requestData.attachmentUrl || ''),
      attachmentType: String(requestData.attachmentType || ''),
      aiConfidence: String(requestData.aiConfidence ?? ''),
      humanReviewRecommended: String(requestData.humanReviewRecommended === true),
      forcedCriticalByUser: String(requestData.forcedCriticalByUser === true),
      requesterName: String(requestData.requesterName || ''),
      latitude: String(requestData.latitude || ''),
      longitude: String(requestData.longitude || ''),
    },
    android: {
      priority: 'high',
      notification: {
        channelId: 'rescue_link_alerts',
      },
    },
    apns: {
      headers: {
        'apns-priority': '10',
      },
    },
  });
}

exports.dispatchEmergencyRequest = onDocumentCreated(
  'emergency_requests/{requestId}',
  async (event) => {
    const requestData = event.data?.data();
    if (!requestData) {
      logger.warn('Emergency request created without data');
      return null;
    }

    const topics = topicsForRequest(requestData);
    logger.info('Dispatching emergency request', {
      requestId: event.params.requestId,
      topics,
    });

    await Promise.allSettled(topics.map((topic) => sendTopicAlert(topic, requestData)));
    return null;
  }
);
