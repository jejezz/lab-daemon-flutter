// 서비스가 낸 로그(ARB 키 + 인자)를 현재 언어 문구로 바꾼다. 서비스는 번역을 모르고, 여기서만 안다.
// 새 로그 키를 서비스에 추가하면 반드시 여기에도 한 줄을 더한다 (test/log_format_test.dart가 빠진 키를 잡는다).

import '../core/lease_time.dart';
import '../core/service.dart';
import '../l10n/app_localizations.dart';

String formatLog(AppLocalizations l, LogEvent e) {
  final a = e.args;
  String s(String name) => '${a[name] ?? ''}';
  int n(String name) => a[name] is int ? a[name] as int : int.tryParse('${a[name]}') ?? 0;
  // hostname처럼 없을 수 있는 값은 빈 문자열로 나와 끝에 공백이 남지 않게 한다.
  String t(String text) => text.trimRight();

  return switch (e.key) {
    'logDhcpDiscover' => t(l.logDhcpDiscover(s('mac'), s('hostname'))),
    'logDhcpOffer' => l.logDhcpOffer(s('ip'), s('mac')),
    'logDhcpRequest' => t(l.logDhcpRequest(s('ip'), s('mac'), s('hostname'))),
    'logDhcpAck' => l.logDhcpAck(s('ip'), s('mac'), _lease(l, a['seconds'])),
    'logDhcpNak' => l.logDhcpNak(s('ip'), s('mac'), _nakReason(l, s('reason'))),
    'logDhcpRelease' => l.logDhcpRelease(s('ip'), s('mac')),
    'logDhcpDecline' => l.logDhcpDecline(s('ip'), s('mac')),
    'logDhcpInform' => l.logDhcpInform(s('ip'), s('mac')),
    'logDhcpPoolExhausted' => l.logDhcpPoolExhausted(s('mac')),
    'logDhcpOtherServer' => l.logDhcpOtherServer(s('mac'), s('server')),
    'logDhcpIgnored' => l.logDhcpIgnored(s('reason')),
    'logDhcpMalformed' => l.logDhcpMalformed(s('from'), s('error')),
    'logDhcpStarted' => l.logDhcpStarted(s('address'), s('start'), s('end'), s('mask')),
    'logDhcpStopped' => l.logDhcpStopped,
    'logDhcpExpired' => l.logDhcpExpired(s('ip'), s('mac')),
    'logDhcpManualRelease' => l.logDhcpManualRelease(s('ip'), s('mac')),
    'logDhcpReserved' => l.logDhcpReserved(s('mac'), s('ip')),
    'logDhcpUnreserved' => l.logDhcpUnreserved(s('mac')),
    'logDhcpPortInUse' => l.logDhcpPortInUse(s('address'), n('port'), s('error')),
    'logDhcpPermissionDenied' => l.logDhcpPermissionDenied(s('address'), n('port'), s('error')),
    'logDhcpBindFailed' => l.logDhcpBindFailed(s('address'), n('port'), s('error')),
    'logDhcpSendFailed' => l.logDhcpSendFailed(s('to'), s('error')),
    'logDhcpPacketIn' => l.logDhcpPacketIn(s('from')),
    'logDhcpProbeStart' => l.logDhcpProbeStart(s('address')),
    'logDhcpProbeFound' => l.logDhcpProbeFound(s('server'), s('ip')),
    'logDhcpProbeNone' => l.logDhcpProbeNone,
    'logDhcpProbeFailed' => l.logDhcpProbeFailed(s('error')),
    'logDhcpPacketOut' => l.logDhcpPacketOut(s('to'), n('port')),
    // 알 수 없는 키는 숨기지 않고 키와 인자를 그대로 보여 준다.
    _ => a.isEmpty ? e.key : '${e.key} $a',
  };
}

String _lease(AppLocalizations l, Object? seconds) =>
    seconds is int ? formatLeaseTime(Duration(seconds: seconds)) : l.leaseUnlimited;

String _nakReason(AppLocalizations l, String reason) => switch (reason) {
      'wrongNetwork' => l.nakReasonWrongNetwork,
      'addressUnavailable' => l.nakReasonAddressUnavailable,
      _ => reason,
    };
