// 서비스가 낸 로그(ARB 키 + 인자)를 현재 언어 문구로 바꾼다. 서비스는 번역을 모르고, 여기서만 안다.
// 새 로그 키를 서비스에 추가하면 반드시 여기에도 한 줄을 더한다 (test/log_format_test.dart가 빠진 키를 잡는다).

import '../core/lease_time.dart';
import '../core/service.dart';
import '../l10n/app_localizations.dart';
import 'format.dart';

String formatLog(AppLocalizations l, LogEvent e) {
  final a = e.args;
  String s(String name) {
    final v = a[name];
    if (v == null) return '';
    if (v is List) return v.join(', ');
    return '$v';
  }

  int n(String name) => a[name] is int ? a[name] as int : int.tryParse('${a[name]}') ?? 0;
  String bytes() => formatBytes(n('bytes'));
  String rate() => formatRate(n('rate'));
  // user·hostname처럼 없을 수 있는 값이 비어서 남는 공백을 지운다.
  String t(String text) => text.replaceAll(RegExp(r'\s+\)'), ')').replaceAll(RegExp(r'\s{2,}'), ' ').trim();

  return switch (e.key) {
    'logDropped' => l.logDropped(n('count')),
    // 시작 전 점검
    'logCheckPortInUse' => l.logCheckPortInUse(s('protocol'), n('port'), s('process').isEmpty ? '?' : s('process'), n('pid')),
    'logCheckFirewallBlocked' => l.logCheckFirewallBlocked(s('profiles'), s('ports')),
    'logCheckOtherDhcpServer' => l.logCheckOtherDhcpServer(s('servers')),
    'logCheckPortsReserved' => l.logCheckPortsReserved(s('range'), s('reserved')),
    'logCheckRuleAdded' => l.logCheckRuleAdded,
    'logCheckRuleFailed' => l.logCheckRuleFailed,
    'logCheckFirewallHint' => l.logCheckFirewallHint,
    // DHCP
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
    'logDhcpPacketOut' => l.logDhcpPacketOut(s('to'), n('port')),
    'logDhcpProbeStart' => l.logDhcpProbeStart(s('address')),
    'logDhcpProbeNone' => l.logDhcpProbeNone,
    'logDhcpProbeFailed' => l.logDhcpProbeFailed(s('error')),
    'logDhcpLeasesLoaded' => l.logDhcpLeasesLoaded(n('count'), n('skipped')),
    'logDhcpLeaseFileFailed' => l.logDhcpLeaseFileFailed(s('error')),
    'logDhcpConflict' => l.logDhcpConflict(s('ip'), s('mac'), n('minutes')),
    // TFTP
    'logTftpStarted' => l.logTftpStarted(s('address'), n('port'), s('root')),
    'logTftpStopped' => l.logTftpStopped,
    'logTftpRrq' => l.logTftpRrq(s('file'), s('client'), s('mode')),
    'logTftpWrq' => l.logTftpWrq(s('file'), s('client'), s('mode')),
    'logTftpSent' => l.logTftpSent(s('file'), s('client'), bytes(), s('seconds'), rate()),
    'logTftpReceived' => l.logTftpReceived(s('file'), s('client'), bytes(), s('seconds'), rate()),
    'logTftpFailed' => l.logTftpFailed(s('file'), s('client'), tftpReason(l, s('reason'))),
    'logTftpBusy' => l.logTftpBusy(s('client'), s('file'), n('limit')),
    'logTftpMalformed' => l.logTftpMalformed(s('from')),
    'logTftpPortInUse' => l.logTftpPortInUse(s('address'), n('port'), s('error')),
    'logTftpPermissionDenied' => l.logTftpPermissionDenied(s('address'), n('port'), s('error')),
    'logTftpBindFailed' => l.logTftpBindFailed(s('address'), n('port'), s('error')),
    'logTftpPacketIn' => l.logTftpPacketIn(s('client')),
    // FTP
    'logFtpStarted' => l.logFtpStarted(s('address'), n('port'), s('root'), s('passive')),
    'logFtpStopped' => l.logFtpStopped,
    'logFtpConnected' => l.logFtpConnected(s('client')),
    'logFtpDisconnected' => t(l.logFtpDisconnected(s('client'), s('user'), n('seconds'))),
    'logFtpLogin' => l.logFtpLogin(s('user'), s('client')),
    'logFtpLoginFailed' => l.logFtpLoginFailed(s('user'), s('client')),
    'logFtpDownload' => l.logFtpDownload(s('file'), s('user'), bytes(), s('seconds'), rate()),
    'logFtpUpload' => l.logFtpUpload(s('file'), s('user'), bytes(), s('seconds'), rate()),
    'logFtpTransferFailed' => l.logFtpTransferFailed(s('file'), s('user'), s('error')),
    'logFtpDenied' => l.logFtpDenied(s('command'), s('path'), s('user'), s('client')),
    'logFtpDeleted' => l.logFtpDeleted(s('path'), s('user')),
    'logFtpMkdir' => l.logFtpMkdir(s('path'), s('user')),
    'logFtpRmdir' => l.logFtpRmdir(s('path'), s('user')),
    'logFtpRenamed' => l.logFtpRenamed(s('from'), s('to'), s('user')),
    'logFtpTooMany' => l.logFtpTooMany(s('client'), n('limit')),
    'logFtpIdleTimeout' => t(l.logFtpIdleTimeout(s('client'), s('user'))),
    'logFtpKicked' => t(l.logFtpKicked(s('client'), s('user'))),
    'logFtpNoPassivePort' => l.logFtpNoPassivePort(s('range')),
    'logFtpPortInUse' => l.logFtpPortInUse(s('address'), n('port'), s('error')),
    'logFtpPermissionDenied' => l.logFtpPermissionDenied(s('address'), n('port'), s('error')),
    'logFtpBindFailed' => l.logFtpBindFailed(s('address'), n('port'), s('error')),
    'logFtpCommand' => l.logFtpCommand(s('client'), s('command')),
    // 알 수 없는 키는 숨기지 않고 키와 인자를 그대로 보여 준다.
    _ => a.isEmpty ? e.key : '${e.key} $a',
  };
}

String _lease(AppLocalizations l, Object? seconds) => seconds is int ? formatLeaseTime(Duration(seconds: seconds)) : l.leaseUnlimited;

String _nakReason(AppLocalizations l, String reason) => switch (reason) {
      'wrongNetwork' => l.nakReasonWrongNetwork,
      'addressUnavailable' => l.nakReasonAddressUnavailable,
      _ => reason,
    };

String tftpReason(AppLocalizations l, String? reason) => switch (reason) {
      'notFound' => l.tftpReasonNotFound,
      'accessViolation' => l.tftpReasonAccessViolation,
      'fileExists' => l.tftpReasonFileExists,
      'writeDisabled' => l.tftpReasonWriteDisabled,
      'timeout' => l.tftpReasonTimeout,
      'clientError' => l.tftpReasonClientError,
      'aborted' => l.tftpReasonAborted,
      'diskFull' => l.tftpReasonDiskFull,
      'io' => l.tftpReasonIo,
      'unsupportedMode' => l.tftpReasonUnsupportedMode,
      _ => reason ?? '',
    };
