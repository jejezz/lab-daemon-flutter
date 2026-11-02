// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get aboutTooltip => 'About';

  @override
  String aboutVersion(String version, String build) {
    return 'Version $version (build $build)';
  }

  @override
  String get aboutOpenSourceLicenses => 'Open Source Licenses';

  @override
  String get aboutRepository => 'GitHub';

  @override
  String get commonClose => 'Close';

  @override
  String aboutMenuItem(String appName) {
    return 'About $appName';
  }

  @override
  String get themeSystem => 'Follow System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get languageSystemShort => 'System';

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionAppearance => 'Appearance';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsMode => 'Mode';

  @override
  String get settingsModeSystem => 'System';

  @override
  String get settingsPalette => 'Color scheme';

  @override
  String get settingsPaletteSaturn => 'Saturn';

  @override
  String get settingsPaletteTeal => 'Teal';

  @override
  String get settingsPaletteAmber => 'Amber';

  @override
  String get settingsPaletteRose => 'Rose';

  @override
  String get settingsPaletteSlate => 'Slate';

  @override
  String get settingsPaletteHighContrast => 'High contrast';

  @override
  String get aboutTagline =>
      'Lab network services, running and visible in one place';

  @override
  String get aboutDescription =>
      'Run DHCP, TFTP and FTP servers and watch connections and logs in real time. A set of simple servers for board flashing and lab setups.';

  @override
  String get homeEmptyTitle => 'No services are running';

  @override
  String get homeEmptyAction => 'Start Service';

  @override
  String get updateCheckMenuItem => 'Check for Updates';

  @override
  String get updateChecking => 'Checking for updates…';

  @override
  String get updateAvailableTitle => 'A new version is available';

  @override
  String updateAvailableBody(String appName, String current, String latest) {
    return '$appName $latest is available. You have $current.';
  }

  @override
  String get updateReleaseNotes => 'What\'s new';

  @override
  String get updateNow => 'Update now';

  @override
  String get updateLater => 'Later';

  @override
  String get updateSkipVersion => 'Skip this version';

  @override
  String get updateDownloading => 'Downloading…';

  @override
  String get updateVerifying => 'Verifying the file…';

  @override
  String updateDownloadProgress(String received, String total) {
    return '$received / $total';
  }

  @override
  String get updateCancel => 'Cancel';

  @override
  String get updateFailedTitle => 'Couldn\'t update';

  @override
  String get updateCheckFailedTitle => 'Couldn\'t check for updates';

  @override
  String get updateErrorNetwork =>
      'Couldn\'t reach the update server. Check your internet connection and try again.';

  @override
  String get updateErrorChecksum =>
      'The downloaded file didn\'t pass verification, so it was not installed. Please try again later.';

  @override
  String get updateErrorInstall => 'Couldn\'t start the installation.';

  @override
  String get updateErrorGeneric =>
      'The update server sent an unexpected response. Please try again later.';

  @override
  String get updateUpToDateTitle => 'You\'re up to date';

  @override
  String updateUpToDateBody(String version) {
    return 'You\'re using version $version.';
  }

  @override
  String get updateUnavailableTitle => 'Install it manually';

  @override
  String updateUnavailableBody(String latest) {
    return 'Version $latest is available, but the app can\'t install it automatically. Please download it from the release page.';
  }

  @override
  String get updateOpenReleasePage => 'Open release page';

  @override
  String get updateBrowserDownloadTitle => 'Downloading in your browser';

  @override
  String updateBrowserDownloadBody(String appName) {
    return 'Your browser is downloading the new version. Open the DMG and drag $appName to the Applications folder. If it\'s running, quit it first and replace the old copy.';
  }

  @override
  String get updateMacosOpenedTitle => 'The installer window is open';

  @override
  String updateMacosOpenedBody(String appName) {
    return 'In the window that opened, drag $appName to the Applications folder. If it\'s running, quit it first and replace the old copy.';
  }

  @override
  String get updateWindowsInstallTitle => 'The installer is open';

  @override
  String updateWindowsInstallBody(String appName) {
    return '$appName must quit before it can be updated. Follow the installer\'s instructions.';
  }

  @override
  String updateQuitApp(String appName) {
    return 'Quit $appName';
  }

  @override
  String get updateLinuxInstallTitle => 'Ready to install';

  @override
  String updateLinuxInstallBody(String appName) {
    return '$appName will quit and install the update, then start again automatically.';
  }

  @override
  String get updateQuitAndInstall => 'Quit and install';

  @override
  String get updateBusyTitle => 'Can\'t update right now';

  @override
  String get updateBusyBody =>
      'A task is in progress. Please try again when it has finished.';

  @override
  String get servicesTitle => 'Services';

  @override
  String get serviceDhcp => 'DHCP';

  @override
  String get serviceStartTooltip => 'Start service';

  @override
  String get serviceStopTooltip => 'Stop service';

  @override
  String get stateStopped => 'Stopped';

  @override
  String get stateStarting => 'Starting';

  @override
  String get stateRunning => 'Running';

  @override
  String get stateStopping => 'Stopping';

  @override
  String get stateError => 'Error';

  @override
  String get statusServer => 'Server';

  @override
  String get statusPool => 'Pool';

  @override
  String get statusGateway => 'Gateway';

  @override
  String get statusLeaseTime => 'Lease time';

  @override
  String statusUsage(int used, int total) {
    return 'In use $used/$total';
  }

  @override
  String statusUptime(String time) {
    return 'Up $time';
  }

  @override
  String statsLine(int discover, int offer, int request, int ack, int nak) {
    return 'Discover $discover · Offer $offer · Request $request · ACK $ack · NAK $nak';
  }

  @override
  String get leaseColIp => 'IP address';

  @override
  String get leaseColMac => 'MAC address';

  @override
  String get leaseColHostname => 'Hostname';

  @override
  String get leaseColState => 'State';

  @override
  String get leaseColRemaining => 'Remaining';

  @override
  String get leaseStateOffered => 'Offered';

  @override
  String get leaseStateBound => 'Bound';

  @override
  String get leaseUnlimited => 'Unlimited';

  @override
  String get leaseRelease => 'Release';

  @override
  String get leaseReleaseAll => 'Release All';

  @override
  String get leaseReleaseAllConfirmTitle => 'Release all leases?';

  @override
  String leaseReleaseAllConfirmBody(int count) {
    return 'This releases $count lease(s). Devices get a new address at their next renewal.';
  }

  @override
  String leaseReleasedSnack(String ip) {
    return 'Released $ip';
  }

  @override
  String leaseReleasedAllSnack(int count) {
    return 'Released $count lease(s)';
  }

  @override
  String get leaseEmptyTitle => 'No leases yet';

  @override
  String get leaseEmptyHint =>
      'Devices show up here when they ask for an address';

  @override
  String get startInvalidSettings =>
      'The DHCP settings are not valid. Check them in Settings.';

  @override
  String startFailed(String error) {
    return 'Could not start the service: $error';
  }

  @override
  String get errorCopy => 'Copy';

  @override
  String get openSettings => 'Open Settings';

  @override
  String get logTitle => 'Log';

  @override
  String get logLevelDebug => 'Debug';

  @override
  String get logLevelInfo => 'Info';

  @override
  String get logLevelWarning => 'Warning';

  @override
  String get logLevelError => 'Error';

  @override
  String get logSearchHint => 'Search log';

  @override
  String get logPause => 'Pause';

  @override
  String get logResume => 'Resume';

  @override
  String get logClear => 'Clear';

  @override
  String get logCopy => 'Copy';

  @override
  String get logCopied => 'Log copied';

  @override
  String get logEmpty => 'Nothing to show';

  @override
  String logPausedBanner(int count) {
    return 'Paused · $count new';
  }

  @override
  String get settingsSectionDhcp => 'DHCP';

  @override
  String get dhcpFieldServerIp => 'Server interface';

  @override
  String get dhcpFieldRangeStart => 'Range start';

  @override
  String get dhcpFieldRangeEnd => 'Range end';

  @override
  String get dhcpFieldMask => 'Subnet mask';

  @override
  String get dhcpFieldGateway => 'Gateway';

  @override
  String get dhcpFieldDns => 'DNS servers';

  @override
  String get dhcpFieldLeaseTime => 'Lease time';

  @override
  String get dhcpFieldDomain => 'Domain name';

  @override
  String get dhcpFieldTftp => 'TFTP server';

  @override
  String get dhcpFieldBootFile => 'Boot file';

  @override
  String get dhcpHintDns => 'Separate with commas';

  @override
  String get dhcpHintLeaseTime => 'e.g. 30s, 10m, 12h, 1d, infinite';

  @override
  String get dhcpHintOptional => 'Optional';

  @override
  String get dhcpDirectedBroadcast => 'Reply to the subnet broadcast address';

  @override
  String get dhcpDirectedBroadcastHint =>
      'Turn on only if replies leave through the wrong interface';

  @override
  String get dhcpLogPackets => 'Write packet hex dumps to the debug log';

  @override
  String get dhcpRestartNote =>
      'While running, only the lease time applies immediately. Restart the service for other changes.';

  @override
  String get dhcpNicNone => 'No interface found';

  @override
  String get dhcpNicRefresh => 'Refresh interfaces';

  @override
  String dhcpNicMissing(String ip) {
    return '$ip (not in the list)';
  }

  @override
  String get fieldErrRequired => 'Required';

  @override
  String get fieldErrInvalidIp => 'Not a valid IPv4 address';

  @override
  String get fieldErrInvalidMask => 'Not a valid subnet mask';

  @override
  String get fieldErrInvalidLeaseTime => 'Use 30s, 10m, 12h, 1d or infinite';

  @override
  String get fieldErrNotInSubnet => 'Outside the subnet';

  @override
  String get fieldErrNotHost =>
      'Network and broadcast addresses cannot be used';

  @override
  String get fieldErrRangeReversed => 'Before the range start';

  @override
  String get fieldErrTooLong => 'Too long';

  @override
  String get nakReasonWrongNetwork => 'address from another network';

  @override
  String get nakReasonAddressUnavailable => 'address not available';

  @override
  String logDhcpDiscover(String mac, String hostname) {
    return 'DISCOVER from $mac $hostname';
  }

  @override
  String logDhcpOffer(String ip, String mac) {
    return 'OFFER $ip to $mac';
  }

  @override
  String logDhcpRequest(String ip, String mac, String hostname) {
    return 'REQUEST $ip from $mac $hostname';
  }

  @override
  String logDhcpAck(String ip, String mac, String lease) {
    return 'ACK $ip to $mac (lease $lease)';
  }

  @override
  String logDhcpNak(String ip, String mac, String reason) {
    return 'NAK $ip to $mac: $reason';
  }

  @override
  String logDhcpRelease(String ip, String mac) {
    return 'RELEASE $ip from $mac';
  }

  @override
  String logDhcpDecline(String ip, String mac) {
    return 'DECLINE $ip from $mac: the client reported a conflict';
  }

  @override
  String logDhcpInform(String ip, String mac) {
    return 'INFORM $ip from $mac';
  }

  @override
  String logDhcpPoolExhausted(String mac) {
    return 'No free address for $mac (pool exhausted)';
  }

  @override
  String logDhcpOtherServer(String mac, String server) {
    return '$mac chose another server, $server';
  }

  @override
  String logDhcpIgnored(String reason) {
    return 'Ignored packet: $reason';
  }

  @override
  String logDhcpMalformed(String from, String error) {
    return 'Malformed packet from $from: $error';
  }

  @override
  String logDhcpStarted(String address, String start, String end, String mask) {
    return 'DHCP server started on $address · $start to $end · $mask';
  }

  @override
  String get logDhcpStopped => 'DHCP server stopped';

  @override
  String logDhcpExpired(String ip, String mac) {
    return 'Lease expired $ip ($mac)';
  }

  @override
  String logDhcpManualRelease(String ip, String mac) {
    return 'Lease released $ip ($mac)';
  }

  @override
  String logDhcpReserved(String mac, String ip) {
    return 'Reservation added $mac = $ip';
  }

  @override
  String logDhcpUnreserved(String mac) {
    return 'Reservation removed $mac';
  }

  @override
  String logDhcpPortInUse(String address, int port, String error) {
    return '$address:$port is already in use: $error';
  }

  @override
  String logDhcpPermissionDenied(String address, int port, String error) {
    return 'No permission to open $address:$port: $error';
  }

  @override
  String logDhcpBindFailed(String address, int port, String error) {
    return 'Could not open $address:$port: $error';
  }

  @override
  String logDhcpSendFailed(String to, String error) {
    return 'Could not send a reply to $to: $error';
  }

  @override
  String logDhcpPacketIn(String from) {
    return 'Received from $from';
  }

  @override
  String logDhcpPacketOut(String to, int port) {
    return 'Sent to $to:$port';
  }

  @override
  String get commonCancel => 'Cancel';

  @override
  String get stateChecking => 'Checking';

  @override
  String get probeConflictTitle => 'Another DHCP server is on this network';

  @override
  String get probeConflictBody =>
      'The servers below answered on the selected interface. Two servers handing out addresses on one network can give devices the wrong address or break their connection.';

  @override
  String probeServerLine(String server, String offered) {
    return '$server (offered $offered)';
  }

  @override
  String get probeConflictAdvice =>
      'Make sure this is an isolated network with devices connected directly to this PC. On a network with an office or home router, it is safer not to start.';

  @override
  String get probeStartAnyway => 'Start Anyway';

  @override
  String get dhcpDetectOthers => 'Check for other DHCP servers before starting';

  @override
  String get dhcpDetectOthersHint =>
      'Warns if another server answers on the same network (about 3 seconds)';

  @override
  String logDhcpProbeStart(String address) {
    return 'Checking for other DHCP servers ($address)';
  }

  @override
  String logDhcpProbeFound(String server, String ip) {
    return 'Another DHCP server found: $server (offered $ip)';
  }

  @override
  String get logDhcpProbeNone => 'No other DHCP server answered';

  @override
  String logDhcpProbeFailed(String error) {
    return 'Could not check for other DHCP servers: $error';
  }
}
