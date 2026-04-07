import '../models/emergency_request_model.dart';
import '../models/responder_model.dart';

class ResponderMatchingService {
  static const Set<String> _alwaysNotifyResponderTypes = <String>{
    'civil defense',
    'off-duty authority',
    'police',
  };

  static bool shouldNotifyResponder({
    required ResponderModel responder,
    required EmergencyRequestModel request,
  }) {
    if (!responder.isAvailable) {
      return false;
    }

    final responderType = responder.responderType.toLowerCase();
    if (_alwaysNotifyResponderTypes.contains(responderType)) {
      return true;
    }

    final responderSkill = responder.skillsArea.toLowerCase();
    final requestSkill = request.recommendedSkill.toLowerCase();
    final category = request.category.toLowerCase();

    if (responderSkill.contains(requestSkill) || requestSkill.contains(responderSkill)) {
      return true;
    }

    final needsMedical = requestSkill.contains('medical') ||
        category.contains('medical') ||
        category.contains('injury');
    if (needsMedical) {
      return responderSkill.contains('medical') ||
          responderType.contains('medical') ||
          responderType.contains('doctor');
    }

    final needsFire = requestSkill.contains('fire') || category.contains('fire');
    if (needsFire) {
      return responderSkill.contains('fire') ||
          responderType.contains('firefighter');
    }

    final needsSafety = requestSkill.contains('women safety') ||
        requestSkill.contains('child safety') ||
        category.contains('women') ||
        category.contains('child');
    if (needsSafety) {
      return responderSkill.contains('women safety') ||
          responderSkill.contains('child safety') ||
          responderType.contains('police');
    }

    final needsShelter = requestSkill.contains('shelter') ||
        requestSkill.contains('evacuation') ||
        category.contains('evacuation') ||
        category.contains('flood');
    if (needsShelter) {
      return responderSkill.contains('shelter') ||
          responderSkill.contains('evacuation') ||
          responderType.contains('shelter host') ||
          responderType.contains('ngo');
    }

    final needsSupply = requestSkill.contains('food') ||
        requestSkill.contains('water') ||
        requestSkill.contains('medicines') ||
        requestSkill.contains('logistics');
    if (needsSupply) {
      return responderSkill.contains('food') ||
          responderSkill.contains('water') ||
          responderSkill.contains('medicines') ||
          responderSkill.contains('logistics') ||
          responderType.contains('logistics provider') ||
          responderType.contains('ngo');
    }

    return responderSkill.contains('general support');
  }

  static double radiusKmForSeverity(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return 15;
      case 'high':
        return 10;
      default:
        return 7;
    }
  }
}