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

function summarizeChatMessage(text) {
  const trimmed = String(text || '').trim();
  if (!trimmed) {
    return 'New media message';
  }
  return trimmed.length > 140 ? `${trimmed.slice(0, 137)}...` : trimmed;
}

function isAiOrSystemMessage(messageData) {
  const senderUid = String(messageData.senderUid || '').trim();
  return messageData.isAi === true ||
    senderUid === 'rescuelink_ai' ||
    messageData.isSystem === true ||
    String(messageData.type || '').toLowerCase() === 'system';
}

function extractParticipantUids(chatData) {
  const fromParticipantUids = Array.isArray(chatData.participantUids)
    ? chatData.participantUids.map((uid) => String(uid || '').trim()).filter(Boolean)
    : [];

  const fromParticipants = Array.isArray(chatData.participants)
    ? chatData.participants
        .map((entry) => String(entry?.uid || '').trim())
        .filter(Boolean)
    : [];

  return Array.from(new Set([...fromParticipantUids, ...fromParticipants]));
}

async function collectTokensForUsers(userUids) {
  const tokenSet = new Set();

  await Promise.all(
    userUids.map(async (uid) => {
      const deviceSnap = await admin
        .firestore()
        .collection('users')
        .doc(uid)
        .collection('devices')
        .get();

      deviceSnap.docs.forEach((doc) => {
        const token = String(doc.data().token || '').trim();
        if (token) {
          tokenSet.add(token);
        }
      });
    })
  );

  return Array.from(tokenSet);
}

exports.dispatchChatMessageNotifications = onDocumentCreated(
  'chats/{sosId}/messages/{messageId}',
  async (event) => {
    const messageData = event.data?.data();
    if (!messageData || isAiOrSystemMessage(messageData)) {
      return null;
    }

    const sosId = String(event.params.sosId || '').trim();
    const senderUid = String(messageData.senderUid || '').trim();
    if (!sosId || !senderUid) {
      return null;
    }

    const chatSnap = await admin.firestore().collection('chats').doc(sosId).get();
    const chatData = chatSnap.data() || {};

    const status = String(chatData.status || 'active').toLowerCase();
    if (status === 'cancelled') {
      return null;
    }

    const notificationPreferences =
      (chatData.notificationPreferences && typeof chatData.notificationPreferences === 'object')
        ? chatData.notificationPreferences
        : {};

    const recipientUids = extractParticipantUids(chatData)
      .filter((uid) => uid !== senderUid)
      .filter((uid) => notificationPreferences[uid] !== false);

    if (recipientUids.length === 0) {
      return null;
    }

    const tokens = await collectTokensForUsers(recipientUids);
    if (tokens.length === 0) {
      return null;
    }

    const senderName = String(messageData.senderName || 'Participant').trim() || 'Participant';
    const previewText = summarizeChatMessage(messageData.text);

    const multicast = {
      tokens,
      notification: {
        title: 'New message in group chat',
        body: `${senderName}: ${previewText}`,
      },
      data: {
        type: 'chat_message',
        chatSosId: sosId,
        senderUid,
        senderName,
        messageId: String(event.params.messageId || ''),
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
    };

    const response = await admin.messaging().sendEachForMulticast(multicast);
    logger.info('Chat message notification dispatch complete', {
      sosId,
      messageId: event.params.messageId,
      successCount: response.successCount,
      failureCount: response.failureCount,
    });

    return null;
  }
);
