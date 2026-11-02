// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get aboutTooltip => '정보';

  @override
  String aboutVersion(String version, String build) {
    return '버전 $version (빌드 $build)';
  }

  @override
  String get aboutOpenSourceLicenses => '오픈소스 라이선스';

  @override
  String get aboutRepository => 'GitHub';

  @override
  String get commonClose => '닫기';

  @override
  String aboutMenuItem(String appName) {
    return '$appName 정보';
  }

  @override
  String get themeSystem => '시스템 설정 따르기';

  @override
  String get themeLight => '라이트';

  @override
  String get themeDark => '다크';

  @override
  String get languageSystemShort => '시스템';

  @override
  String get settingsTooltip => '설정';

  @override
  String get settingsTitle => '설정';

  @override
  String get settingsSectionAppearance => '외형';

  @override
  String get settingsLanguage => '언어';

  @override
  String get settingsMode => '모드';

  @override
  String get settingsModeSystem => '시스템';

  @override
  String get settingsPalette => '색 구성';

  @override
  String get settingsPaletteSaturn => '새턴';

  @override
  String get settingsPaletteTeal => '청록';

  @override
  String get settingsPaletteAmber => '호박';

  @override
  String get settingsPaletteRose => '장미';

  @override
  String get settingsPaletteSlate => '슬레이트';

  @override
  String get settingsPaletteHighContrast => '고대비';

  @override
  String get aboutTagline => '랩용 네트워크 서비스를 한 곳에서 켜고 지켜봅니다';

  @override
  String get aboutDescription =>
      'DHCP, TFTP, FTP 서버를 켜고 접속 현황과 로그를 실시간으로 확인합니다. 보드 플래싱과 랩 환경에서 쓰는 간이 서버 모음입니다.';

  @override
  String get homeEmptyTitle => '실행 중인 서비스가 없어요';

  @override
  String get homeEmptyAction => '서비스 시작';

  @override
  String get updateCheckMenuItem => '업데이트 확인';

  @override
  String get updateChecking => '업데이트를 확인하는 중…';

  @override
  String get updateAvailableTitle => '새 버전이 있습니다';

  @override
  String updateAvailableBody(String appName, String current, String latest) {
    return '$appName $latest 버전이 나왔습니다. (현재 $current)';
  }

  @override
  String get updateReleaseNotes => '변경 내용';

  @override
  String get updateNow => '지금 업데이트';

  @override
  String get updateLater => '나중에';

  @override
  String get updateSkipVersion => '이 버전 건너뛰기';

  @override
  String get updateDownloading => '내려받는 중…';

  @override
  String get updateVerifying => '파일을 확인하는 중…';

  @override
  String updateDownloadProgress(String received, String total) {
    return '$received / $total';
  }

  @override
  String get updateCancel => '취소';

  @override
  String get updateFailedTitle => '업데이트하지 못했습니다';

  @override
  String get updateCheckFailedTitle => '업데이트를 확인하지 못했습니다';

  @override
  String get updateErrorNetwork =>
      '업데이트 서버에 연결하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도해 주세요.';

  @override
  String get updateErrorChecksum =>
      '내려받은 파일이 올바르지 않아 설치하지 않았습니다. 잠시 뒤에 다시 시도해 주세요.';

  @override
  String get updateErrorInstall => '설치를 시작하지 못했습니다.';

  @override
  String get updateErrorGeneric =>
      '업데이트 서버에서 예상하지 못한 응답을 받았습니다. 잠시 뒤에 다시 시도해 주세요.';

  @override
  String get updateUpToDateTitle => '최신 버전입니다';

  @override
  String updateUpToDateBody(String version) {
    return '$version 버전을 사용 중입니다.';
  }

  @override
  String get updateUnavailableTitle => '직접 설치해 주세요';

  @override
  String updateUnavailableBody(String latest) {
    return '$latest 버전이 있지만 앱에서 자동으로 설치할 수 없습니다. 릴리스 페이지에서 받아 주세요.';
  }

  @override
  String get updateOpenReleasePage => '릴리스 페이지 열기';

  @override
  String get updateBrowserDownloadTitle => '브라우저에서 내려받습니다';

  @override
  String updateBrowserDownloadBody(String appName) {
    return '브라우저가 새 버전 내려받기를 시작합니다. 받은 DMG를 열어 $appName 을(를) Applications 폴더로 끌어다 놓아 주세요. 실행 중이면 종료한 뒤 덮어쓰세요.';
  }

  @override
  String get updateMacosOpenedTitle => '설치 창이 열렸습니다';

  @override
  String updateMacosOpenedBody(String appName) {
    return '열린 창에서 $appName 을(를) Applications 폴더로 끌어다 놓아 주세요. 실행 중이면 종료한 뒤 덮어쓰세요.';
  }

  @override
  String get updateWindowsInstallTitle => '설치 프로그램을 열었습니다';

  @override
  String updateWindowsInstallBody(String appName) {
    return '설치하려면 $appName 을(를) 종료해야 합니다. 설치 프로그램의 안내를 따라 주세요.';
  }

  @override
  String updateQuitApp(String appName) {
    return '$appName 종료';
  }

  @override
  String get updateLinuxInstallTitle => '설치를 준비했습니다';

  @override
  String updateLinuxInstallBody(String appName) {
    return '$appName 을(를) 종료하고 설치합니다. 설치가 끝나면 자동으로 다시 시작됩니다.';
  }

  @override
  String get updateQuitAndInstall => '종료하고 설치';

  @override
  String get updateBusyTitle => '지금은 업데이트할 수 없습니다';

  @override
  String get updateBusyBody => '작업이 진행 중입니다. 끝난 뒤에 다시 시도해 주세요.';

  @override
  String get servicesTitle => '서비스';

  @override
  String get serviceDhcp => 'DHCP';

  @override
  String get serviceStartTooltip => '서비스 시작';

  @override
  String get serviceStopTooltip => '서비스 중지';

  @override
  String get stateStopped => '중지됨';

  @override
  String get stateStarting => '시작 중';

  @override
  String get stateRunning => '실행 중';

  @override
  String get stateStopping => '중지 중';

  @override
  String get stateError => '오류';

  @override
  String get statusServer => '서버';

  @override
  String get statusPool => '범위';

  @override
  String get statusGateway => '게이트웨이';

  @override
  String get statusLeaseTime => 'Lease Time';

  @override
  String statusUsage(int used, int total) {
    return '사용 $used/$total';
  }

  @override
  String statusUptime(String time) {
    return '가동 $time';
  }

  @override
  String statsLine(int discover, int offer, int request, int ack, int nak) {
    return 'Discover $discover · Offer $offer · Request $request · ACK $ack · NAK $nak';
  }

  @override
  String get leaseColIp => 'IP 주소';

  @override
  String get leaseColMac => 'MAC 주소';

  @override
  String get leaseColHostname => '호스트 이름';

  @override
  String get leaseColState => '상태';

  @override
  String get leaseColRemaining => '남은 시간';

  @override
  String get leaseStateOffered => '제안됨';

  @override
  String get leaseStateBound => '사용 중';

  @override
  String get leaseUnlimited => '무제한';

  @override
  String get leaseRelease => '해제';

  @override
  String get leaseReleaseAll => '전체 해제';

  @override
  String get leaseReleaseAllConfirmTitle => '모든 Lease를 해제할까요?';

  @override
  String leaseReleaseAllConfirmBody(int count) {
    return '$count개의 Lease를 해제해요. 장비는 다음 갱신 때 새 주소를 받아요.';
  }

  @override
  String leaseReleasedSnack(String ip) {
    return '$ip를 해제했어요';
  }

  @override
  String leaseReleasedAllSnack(int count) {
    return 'Lease $count개를 해제했어요';
  }

  @override
  String get leaseEmptyTitle => '아직 Lease가 없어요';

  @override
  String get leaseEmptyHint => '장비가 DHCP로 주소를 요청하면 여기에 나타나요';

  @override
  String get startInvalidSettings => 'DHCP 설정이 올바르지 않아요. 설정에서 확인해 주세요.';

  @override
  String startFailed(String error) {
    return '서비스를 시작하지 못했어요: $error';
  }

  @override
  String get errorCopy => '복사';

  @override
  String get openSettings => '설정 열기';

  @override
  String get logTitle => '로그';

  @override
  String get logLevelDebug => '디버그';

  @override
  String get logLevelInfo => '정보';

  @override
  String get logLevelWarning => '경고';

  @override
  String get logLevelError => '오류';

  @override
  String get logSearchHint => '로그 검색';

  @override
  String get logPause => '일시정지';

  @override
  String get logResume => '계속';

  @override
  String get logClear => '지우기';

  @override
  String get logCopy => '복사';

  @override
  String get logCopied => '로그를 복사했어요';

  @override
  String get logEmpty => '표시할 로그가 없어요';

  @override
  String logPausedBanner(int count) {
    return '일시정지됨 · 새 로그 $count개';
  }

  @override
  String get settingsSectionDhcp => 'DHCP';

  @override
  String get dhcpFieldServerIp => '서버 NIC';

  @override
  String get dhcpFieldRangeStart => '시작 주소';

  @override
  String get dhcpFieldRangeEnd => '끝 주소';

  @override
  String get dhcpFieldMask => '서브넷 마스크';

  @override
  String get dhcpFieldGateway => '게이트웨이';

  @override
  String get dhcpFieldDns => 'DNS 서버';

  @override
  String get dhcpFieldLeaseTime => 'Lease Time';

  @override
  String get dhcpFieldDomain => '도메인 이름';

  @override
  String get dhcpFieldTftp => 'TFTP 서버';

  @override
  String get dhcpFieldBootFile => '부팅 파일';

  @override
  String get dhcpHintDns => '쉼표로 구분';

  @override
  String get dhcpHintLeaseTime => '예: 30s, 10m, 12h, 1d, infinite';

  @override
  String get dhcpHintOptional => '선택';

  @override
  String get dhcpDirectedBroadcast => '서브넷 브로드캐스트로 응답';

  @override
  String get dhcpDirectedBroadcastHint => '응답이 엉뚱한 NIC로 나갈 때만 켜세요';

  @override
  String get dhcpLogPackets => '패킷 16진수 덤프를 디버그 로그에 기록';

  @override
  String get dhcpRestartNote =>
      '실행 중에는 Lease Time만 바로 적용돼요. 나머지는 서비스를 다시 시작하면 적용돼요.';

  @override
  String get dhcpNicNone => 'NIC를 찾지 못했어요';

  @override
  String get dhcpNicRefresh => 'NIC 새로고침';

  @override
  String dhcpNicMissing(String ip) {
    return '$ip (목록에 없음)';
  }

  @override
  String get fieldErrRequired => '값이 필요해요';

  @override
  String get fieldErrInvalidIp => '올바른 IPv4 주소가 아니에요';

  @override
  String get fieldErrInvalidMask => '올바른 서브넷 마스크가 아니에요';

  @override
  String get fieldErrInvalidLeaseTime =>
      '30s, 10m, 12h, 1d, infinite 중 하나여야 해요';

  @override
  String get fieldErrNotInSubnet => '서브넷 밖의 주소예요';

  @override
  String get fieldErrNotHost => '네트워크·브로드캐스트 주소는 쓸 수 없어요';

  @override
  String get fieldErrRangeReversed => '시작 주소보다 앞서요';

  @override
  String get fieldErrTooLong => '너무 길어요';

  @override
  String get nakReasonWrongNetwork => '다른 네트워크의 주소';

  @override
  String get nakReasonAddressUnavailable => '줄 수 없는 주소';

  @override
  String logDhcpDiscover(String mac, String hostname) {
    return 'DISCOVER $mac $hostname';
  }

  @override
  String logDhcpOffer(String ip, String mac) {
    return 'OFFER $ip → $mac';
  }

  @override
  String logDhcpRequest(String ip, String mac, String hostname) {
    return 'REQUEST $ip ← $mac $hostname';
  }

  @override
  String logDhcpAck(String ip, String mac, String lease) {
    return 'ACK $ip → $mac (Lease $lease)';
  }

  @override
  String logDhcpNak(String ip, String mac, String reason) {
    return 'NAK $ip → $mac: $reason';
  }

  @override
  String logDhcpRelease(String ip, String mac) {
    return 'RELEASE $ip ← $mac';
  }

  @override
  String logDhcpDecline(String ip, String mac) {
    return 'DECLINE $ip ← $mac: 클라이언트가 주소 충돌을 알렸어요';
  }

  @override
  String logDhcpInform(String ip, String mac) {
    return 'INFORM $ip ← $mac';
  }

  @override
  String logDhcpPoolExhausted(String mac) {
    return '$mac에 줄 주소가 없어요 (풀이 가득 찼어요)';
  }

  @override
  String logDhcpOtherServer(String mac, String server) {
    return '$mac이(가) 다른 서버 $server를 골랐어요';
  }

  @override
  String logDhcpIgnored(String reason) {
    return '무시한 패킷: $reason';
  }

  @override
  String logDhcpMalformed(String from, String error) {
    return '$from에서 온 잘못된 패킷: $error';
  }

  @override
  String logDhcpStarted(String address, String start, String end, String mask) {
    return 'DHCP 서버 시작 $address · $start ~ $end · $mask';
  }

  @override
  String get logDhcpStopped => 'DHCP 서버를 중지했어요';

  @override
  String logDhcpExpired(String ip, String mac) {
    return 'Lease 만료 $ip ($mac)';
  }

  @override
  String logDhcpManualRelease(String ip, String mac) {
    return 'Lease 해제 $ip ($mac)';
  }

  @override
  String logDhcpReserved(String mac, String ip) {
    return '예약 추가 $mac = $ip';
  }

  @override
  String logDhcpUnreserved(String mac) {
    return '예약 삭제 $mac';
  }

  @override
  String logDhcpPortInUse(String address, int port, String error) {
    return '$address:$port를 다른 프로그램이 쓰고 있어요: $error';
  }

  @override
  String logDhcpPermissionDenied(String address, int port, String error) {
    return '$address:$port를 열 권한이 없어요: $error';
  }

  @override
  String logDhcpBindFailed(String address, int port, String error) {
    return '$address:$port를 열지 못했어요: $error';
  }

  @override
  String logDhcpSendFailed(String to, String error) {
    return '$to로 응답을 보내지 못했어요: $error';
  }

  @override
  String logDhcpPacketIn(String from) {
    return '수신 $from';
  }

  @override
  String logDhcpPacketOut(String to, int port) {
    return '송신 $to:$port';
  }

  @override
  String get commonCancel => '취소';

  @override
  String get stateChecking => '확인 중';

  @override
  String get probeConflictTitle => '같은 망에 다른 DHCP 서버가 있어요';

  @override
  String get probeConflictBody =>
      '선택한 NIC에서 아래 서버가 응답했어요. 서버 두 대가 같은 망에서 주소를 나눠 주면 장비가 엉뚱한 주소를 받거나 연결이 불안정해질 수 있어요.';

  @override
  String probeServerLine(String server, String offered) {
    return '$server (제안 $offered)';
  }

  @override
  String get probeConflictAdvice =>
      '장비를 이 PC에 직접 연결한 격리된 망이 맞는지 확인하세요. 회사나 집 공유기가 있는 망이라면 켜지 않는 것이 안전해요.';

  @override
  String get probeStartAnyway => '그래도 시작';

  @override
  String get dhcpDetectOthers => '시작하기 전에 다른 DHCP 서버 확인';

  @override
  String get dhcpDetectOthersHint => '같은 망에서 응답하는 서버가 있으면 경고해요 (약 3초)';

  @override
  String logDhcpProbeStart(String address) {
    return '다른 DHCP 서버 확인 중 ($address)';
  }

  @override
  String logDhcpProbeFound(String server, String ip) {
    return '다른 DHCP 서버 발견: $server (제안 $ip)';
  }

  @override
  String get logDhcpProbeNone => '다른 DHCP 서버의 응답이 없었어요';

  @override
  String logDhcpProbeFailed(String error) {
    return '다른 DHCP 서버를 확인하지 못했어요: $error';
  }
}
