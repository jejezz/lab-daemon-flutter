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
  String get homeEmptyTitle => 'The service is stopped';

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
  String startFailed(String error) {
    return 'Could not start the service: $error';
  }

  @override
  String get errorCopy => 'Copy';

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
  String get logDhcpProbeNone => 'No other DHCP server answered';

  @override
  String logDhcpProbeFailed(String error) {
    return 'Could not check for other DHCP servers: $error';
  }

  @override
  String get serviceTftp => 'TFTP';

  @override
  String get serviceFtp => 'FTP';

  @override
  String panelTitle(String service) {
    return '$service settings';
  }

  @override
  String get runningLockedNote =>
      'Settings are locked while the service runs. Stop it to make changes.';

  @override
  String get fieldBindNic => 'Interface';

  @override
  String get fieldAllNics => 'All interfaces (0.0.0.0)';

  @override
  String get fieldAllNicsWarning =>
      'Listens on every interface, including your office network.';

  @override
  String get fieldPort => 'Port';

  @override
  String get fieldRootDir => 'Root folder';

  @override
  String get fieldBrowse => 'Browse';

  @override
  String get sectionAdvanced => 'Advanced';

  @override
  String get fieldErrDirMissing => 'Folder does not exist';

  @override
  String get fieldErrInvalidPort => 'Must be 1 to 65535';

  @override
  String get fieldErrInvalidNumber => 'Number out of range';

  @override
  String startInvalidSettingsFor(String service) {
    return 'The $service settings are not valid. Check the settings on the left.';
  }

  @override
  String get tftpAllowWrite => 'Allow uploads';

  @override
  String get tftpAllowWriteHint =>
      'Clients can write files into the root folder';

  @override
  String get tftpAllowOverwrite => 'Allow overwriting existing files';

  @override
  String get tftpMaxBlockSize => 'Max block size (bytes)';

  @override
  String get tftpMaxWindow => 'Max window (blocks)';

  @override
  String get tftpTimeout => 'Retransmit timeout (ms)';

  @override
  String get tftpMaxTransfers => 'Concurrent transfers';

  @override
  String get tftpLogPackets => 'Write request hex dumps to the debug log';

  @override
  String get tftpColClient => 'Client';

  @override
  String get tftpColFile => 'File';

  @override
  String get tftpColDirection => 'Direction';

  @override
  String get tftpColProgress => 'Progress';

  @override
  String get tftpColRate => 'Rate';

  @override
  String get tftpColState => 'State';

  @override
  String get tftpDownload => 'Sent';

  @override
  String get tftpUpload => 'Received';

  @override
  String get tftpStateActive => 'Active';

  @override
  String get tftpStateDone => 'Done';

  @override
  String get tftpStateFailed => 'Failed';

  @override
  String get tftpAbort => 'Abort';

  @override
  String get tftpClearRecent => 'Clear finished';

  @override
  String get tftpEmptyTitle => 'No transfers yet';

  @override
  String get tftpEmptyHint =>
      'Devices show up here when they request a file over TFTP';

  @override
  String tftpSummary(
    int active,
    int completed,
    int failed,
    String sent,
    String received,
  ) {
    return 'Active $active · Done $completed · Failed $failed · Sent $sent · Received $received';
  }

  @override
  String get tftpReasonNotFound => 'file not found';

  @override
  String get tftpReasonAccessViolation => 'access denied';

  @override
  String get tftpReasonFileExists => 'file already exists';

  @override
  String get tftpReasonWriteDisabled => 'uploads disabled';

  @override
  String get tftpReasonTimeout => 'timed out';

  @override
  String get tftpReasonClientError => 'cancelled by the client';

  @override
  String get tftpReasonAborted => 'aborted';

  @override
  String get tftpReasonDiskFull => 'disk full';

  @override
  String get tftpReasonIo => 'file I/O error';

  @override
  String get tftpReasonUnsupportedMode => 'unsupported mode';

  @override
  String get ftpAccount => 'Account';

  @override
  String get ftpUsername => 'Username';

  @override
  String get ftpPassword => 'Password';

  @override
  String get ftpPasswordSet =>
      'A password is set. Type a new one to change it.';

  @override
  String get ftpPasswordHint => 'Stored only as a salted hash';

  @override
  String get ftpAllowAnonymous => 'Allow anonymous login';

  @override
  String get ftpAllowWrite => 'Allow writing (upload, delete, rename)';

  @override
  String get ftpAnonymousWriteWarning => 'Anonymous users can change files too';

  @override
  String get ftpPassiveStart => 'Passive ports from';

  @override
  String get ftpPassiveEnd => 'Passive ports to';

  @override
  String get ftpPassiveHint => 'This range must also be open in the firewall';

  @override
  String get ftpMaxConnections => 'Max connections';

  @override
  String get ftpIdleTimeout => 'Idle timeout (seconds)';

  @override
  String get ftpLogCommands =>
      'Write every command to the debug log (passwords hidden)';

  @override
  String get ftpColClient => 'Client';

  @override
  String get ftpColUser => 'User';

  @override
  String get ftpColDir => 'Folder';

  @override
  String get ftpColActivity => 'Activity';

  @override
  String get ftpColTraffic => 'In / out';

  @override
  String get ftpColConnected => 'Connected';

  @override
  String get ftpNotLoggedIn => 'Not logged in';

  @override
  String get ftpDisconnect => 'Disconnect';

  @override
  String get ftpClosed => 'Closed';

  @override
  String ftpUploading(String file) {
    return 'Uploading $file';
  }

  @override
  String ftpDownloading(String file) {
    return 'Downloading $file';
  }

  @override
  String get ftpEmptyTitle => 'No clients connected';

  @override
  String get ftpEmptyHint => 'Clients show up here when they connect';

  @override
  String ftpSummary(int open, int total, String received, String sent) {
    return 'Open $open · Total $total · In $received · Out $sent';
  }

  @override
  String get checkTitleBlocked => 'The service cannot start';

  @override
  String get checkTitleWarning => 'Check before starting';

  @override
  String checkPortInUse(String protocol, int port, String process, int pid) {
    return '$protocol $port is used by another program: $process (PID $pid)';
  }

  @override
  String checkFirewall(String profiles, String ports) {
    return 'Windows Firewall may block incoming $ports on the $profiles profile. There is no allow rule for this program.';
  }

  @override
  String checkOtherDhcp(String servers) {
    return 'Another DHCP server is on this network: $servers';
  }

  @override
  String checkPortsReserved(String range, String reserved, int free) {
    return 'Windows reserves $reserved of the passive range $range ($free ports left).';
  }

  @override
  String get checkPortsReservedAdvice =>
      'Pick another range (for example 40000-40199). See reserved ranges with: netsh int ipv4 show excludedportrange protocol=tcp';

  @override
  String get checkAddRule => 'Add Firewall Rule';

  @override
  String get checkAddRuleHint => 'Windows asks for administrator approval';

  @override
  String get checkRuleAdded => 'Firewall rule added';

  @override
  String logDropped(int count) {
    return 'Too many log lines: skipped $count';
  }

  @override
  String logCheckPortInUse(String protocol, int port, String process, int pid) {
    return '$protocol $port is used by $process (PID $pid)';
  }

  @override
  String logCheckFirewallBlocked(String profiles, String ports) {
    return 'No firewall allow rule: $profiles profile, $ports';
  }

  @override
  String logCheckOtherDhcpServer(String servers) {
    return 'Another DHCP server found: $servers';
  }

  @override
  String logCheckPortsReserved(String range, String reserved) {
    return 'Reserved ports: $reserved of $range';
  }

  @override
  String get logCheckRuleAdded => 'Firewall rule added';

  @override
  String get logCheckRuleFailed =>
      'Could not add the firewall rule (declined or failed)';

  @override
  String logTftpStarted(String address, int port, String root) {
    return 'TFTP server started on $address:$port · $root';
  }

  @override
  String get logTftpStopped => 'TFTP server stopped';

  @override
  String logTftpRrq(String file, String client, String mode) {
    return 'Read request $file from $client ($mode)';
  }

  @override
  String logTftpWrq(String file, String client, String mode) {
    return 'Write request $file from $client ($mode)';
  }

  @override
  String logTftpSent(
    String file,
    String client,
    String bytes,
    String seconds,
    String rate,
  ) {
    return 'Sent $file to $client · $bytes · ${seconds}s · $rate';
  }

  @override
  String logTftpReceived(
    String file,
    String client,
    String bytes,
    String seconds,
    String rate,
  ) {
    return 'Received $file from $client · $bytes · ${seconds}s · $rate';
  }

  @override
  String logTftpFailed(String file, String client, String reason) {
    return 'Failed $file ($client): $reason';
  }

  @override
  String logTftpBusy(String client, String file, int limit) {
    return 'Refused $file from $client (more than $limit transfers)';
  }

  @override
  String logTftpMalformed(String from) {
    return 'Malformed request from $from';
  }

  @override
  String logTftpPortInUse(String address, int port, String error) {
    return '$address:$port is already in use: $error';
  }

  @override
  String logTftpPermissionDenied(String address, int port, String error) {
    return 'No permission to open $address:$port: $error';
  }

  @override
  String logTftpBindFailed(String address, int port, String error) {
    return 'Could not open $address:$port: $error';
  }

  @override
  String logTftpPacketIn(String client) {
    return 'Request packet from $client';
  }

  @override
  String logFtpStarted(String address, int port, String root, String passive) {
    return 'FTP server started on $address:$port · $root · passive $passive';
  }

  @override
  String get logFtpStopped => 'FTP server stopped';

  @override
  String logFtpConnected(String client) {
    return 'Connected $client';
  }

  @override
  String logFtpDisconnected(String client, String user, int seconds) {
    return 'Disconnected $client $user (${seconds}s)';
  }

  @override
  String logFtpLogin(String user, String client) {
    return 'Logged in $user ($client)';
  }

  @override
  String logFtpLoginFailed(String user, String client) {
    return 'Login failed $user ($client)';
  }

  @override
  String logFtpDownload(
    String file,
    String user,
    String bytes,
    String seconds,
    String rate,
  ) {
    return 'Downloaded $file by $user · $bytes · ${seconds}s · $rate';
  }

  @override
  String logFtpUpload(
    String file,
    String user,
    String bytes,
    String seconds,
    String rate,
  ) {
    return 'Uploaded $file by $user · $bytes · ${seconds}s · $rate';
  }

  @override
  String logFtpTransferFailed(String file, String user, String error) {
    return 'Transfer failed $file ($user): $error';
  }

  @override
  String logFtpDenied(String command, String path, String user, String client) {
    return 'Denied $command $path ($user, $client)';
  }

  @override
  String logFtpDeleted(String path, String user) {
    return 'Deleted $path ($user)';
  }

  @override
  String logFtpMkdir(String path, String user) {
    return 'Created folder $path ($user)';
  }

  @override
  String logFtpRmdir(String path, String user) {
    return 'Removed folder $path ($user)';
  }

  @override
  String logFtpRenamed(String from, String to, String user) {
    return 'Renamed $from to $to ($user)';
  }

  @override
  String logFtpTooMany(String client, int limit) {
    return 'Refused $client (more than $limit connections)';
  }

  @override
  String logFtpIdleTimeout(String client, String user) {
    return 'Idle timeout $client $user';
  }

  @override
  String logFtpKicked(String client, String user) {
    return 'Disconnected by you $client $user';
  }

  @override
  String logFtpNoPassivePort(String range) {
    return 'No free passive port in $range';
  }

  @override
  String logFtpPortInUse(String address, int port, String error) {
    return '$address:$port is already in use: $error';
  }

  @override
  String logFtpPermissionDenied(String address, int port, String error) {
    return 'No permission to open $address:$port: $error';
  }

  @override
  String logFtpBindFailed(String address, int port, String error) {
    return 'Could not open $address:$port: $error';
  }

  @override
  String logFtpCommand(String client, String command) {
    return '$client › $command';
  }

  @override
  String updateMoreChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'and $count more',
      one: 'and 1 more',
    );
    return '$_temp0';
  }

  @override
  String get updateViewReleaseNotes => 'Release notes';

  @override
  String get logLevelTooltip => 'Minimum level';

  @override
  String get firewallHelpButton => 'How to Fix';

  @override
  String get firewallHintChip => 'Firewall help';

  @override
  String get firewallHelpTitle => 'Allow through Windows Firewall';

  @override
  String firewallHelpWhy(String ports, String profiles) {
    return 'This program needs a Windows Firewall exception to receive $ports. There is no allow rule on the $profiles profile.';
  }

  @override
  String get firewallHelpProgram => 'Program';

  @override
  String get firewallHelpAutoTitle => '1. Add automatically (recommended)';

  @override
  String get firewallHelpAutoBody =>
      'Windows asks for administrator approval. When you approve, a rule allowing this program on every network profile is added.';

  @override
  String firewallHelpManualTitle(String os) {
    return '2. Allow it yourself ($os)';
  }

  @override
  String get firewallStepsWin11 =>
      'Start → Settings → Privacy & security → Windows Security → Firewall & network protection\n[Allow an app through firewall] → [Change settings] → [Allow another app…]\n[Browse…] to the program above, then [Add]\nTick both [Private] and [Public] for Lab Daemon and press [OK]';

  @override
  String get firewallStepsWin10 =>
      'Start → Settings → Update & Security → Windows Security → Firewall & network protection\n[Allow an app through firewall] → [Change settings] → [Allow another app…]\n[Browse…] to the program above, then [Add]\nTick both [Private] and [Public] for Lab Daemon and press [OK]';

  @override
  String get firewallOpenAllowedApps => 'Open Allowed Apps';

  @override
  String get firewallHelpCommandTitle =>
      '3. Add with a command (PowerShell or Command Prompt as administrator)';

  @override
  String get firewallHelpInstallerNote =>
      'Lab Daemon installed with the installer gets this rule automatically. A copy run from another place (such as a development build) has a different path and needs its own rule.';

  @override
  String get firewallHelpPolicyNote =>
      'On managed PCs, policy may block adding rules. Ask your IT administrator to allow the program and ports above.';

  @override
  String get commandCopied => 'Command copied';

  @override
  String get logCheckFirewallHint =>
      'See [Firewall help] at the top of the service view for how to fix this';

  @override
  String get openRootFolder => 'Open root folder in Explorer';

  @override
  String get logCapacityTooltip => 'Log lines to keep';

  @override
  String logCapacityLines(int count) {
    return '$count lines';
  }

  @override
  String fieldPortDefault(int port) {
    return 'Port (default $port)';
  }

  @override
  String get panelCollapseTooltip => 'Collapse settings (Ctrl+B)';

  @override
  String get panelExpandTooltip => 'Expand settings (Ctrl+B)';

  @override
  String get panelRailLabel => 'Settings';

  @override
  String get settingsTextScale => 'Text size';

  @override
  String get settingsTextScaleReset => 'Reset to default';

  @override
  String logDhcpLeasesLoaded(int count, int skipped) {
    return 'Restored $count saved lease(s) ($skipped skipped)';
  }

  @override
  String logDhcpLeaseFileFailed(String error) {
    return 'Could not read or write the lease file: $error';
  }

  @override
  String get dhcpPersistLeases => 'Keep leases across restarts';

  @override
  String get dhcpPersistLeasesHint =>
      'Saves leases to a file and reuses them when the service starts again (expired or out-of-range ones are dropped)';

  @override
  String get fieldErrInvalidMac =>
      'Not a MAC address (for example aa:bb:cc:00:11:22)';

  @override
  String get fieldErrDuplicate =>
      'This MAC is already reserved, or the address matches the server, the gateway or another reservation';

  @override
  String get dhcpReservations => 'Reserved addresses';

  @override
  String get dhcpReservationsHint =>
      'Always gives the same IP to a MAC address. You can add or remove them while the service runs.';

  @override
  String get dhcpReserveMac => 'MAC address';

  @override
  String get dhcpReserveIp => 'Reserved IP';

  @override
  String get dhcpReserveAdd => 'Add';

  @override
  String get dhcpReserveRemove => 'Remove reservation';

  @override
  String get dhcpReservationNone => 'No reserved addresses';

  @override
  String get leaseReserve => 'Reserve address';

  @override
  String get leaseReservedTooltip => 'Reserved address';

  @override
  String leaseReserveDone(String mac, String ip) {
    return 'Reserved $ip for $mac';
  }

  @override
  String reserveFailed(String error) {
    return 'Could not reserve: $error';
  }

  @override
  String logDhcpConflict(String ip, String mac, int minutes) {
    return 'Got a reply from $ip, so it was not offered (asked by $mac) — skipping it for $minutes min';
  }

  @override
  String get dhcpConflictCheck => 'Check an address before offering it (ping)';

  @override
  String get dhcpConflictCheckHint =>
      'Pings the address before handing it out so it never collides with a device using a fixed IP. An unused address waits about 0.3 s for a reply. Devices that block ICMP are not found.';

  @override
  String get logToFile => 'Also save the log to a file';

  @override
  String get logToFileHint =>
      'One file per day (in English), kept for 14 days. Writing continues while this app runs, even when the service is stopped.';

  @override
  String get logOpenFolder => 'Open log folder';

  @override
  String get dhcpUseTftpAddress => 'Fill in the TFTP service address';

  @override
  String get dhcpPickBootFile => 'Choose from the TFTP root folder';

  @override
  String get dhcpBootPickTitle => 'Choose a boot file';

  @override
  String get dhcpBootPickSearch => 'Search file names';

  @override
  String get dhcpBootPickEmpty => 'No matching files';

  @override
  String get dhcpBootPickNoRoot => 'Set the TFTP service root folder first';

  @override
  String dhcpBootPickMore(int count) {
    return 'Showing the first $count. Narrow it down with the search';
  }

  @override
  String dhcpTftpPortNote(String port) {
    return 'The TFTP service uses port $port, so boards may not find it (usually 69)';
  }

  @override
  String get fieldRootDirDropHint =>
      'You can also drag a folder onto this field';

  @override
  String get serviceHttp => 'HTTP';

  @override
  String get httpAllowListing => 'Show folder listings';

  @override
  String get httpAllowListingHint =>
      'Opening a folder address lists its files (when off, only an index.html is served)';

  @override
  String get httpAllowWrite => 'Allow uploads (PUT)';

  @override
  String get httpAllowWriteHint =>
      'Clients can upload into the root folder with curl -T file http://address/name';

  @override
  String get httpAllowOverwrite => 'Allow overwriting existing files';

  @override
  String get httpMaxConnections => 'Max concurrent requests';

  @override
  String get httpIdleTimeout => 'Idle connection timeout (s)';

  @override
  String get httpColClient => 'Client';

  @override
  String get httpColRequest => 'Request';

  @override
  String get httpColStatus => 'Reply';

  @override
  String get httpColProgress => 'Progress';

  @override
  String get httpColRate => 'Rate';

  @override
  String get httpColState => 'State';

  @override
  String get httpEmptyTitle => 'No requests yet';

  @override
  String get httpEmptyHint =>
      'Devices show up here when they request a file over HTTP';

  @override
  String httpSummary(
    int active,
    int completed,
    int failed,
    String sent,
    String received,
  ) {
    return 'Active $active · OK $completed · Failed $failed · Sent $sent · Received $received';
  }

  @override
  String get httpCopyAddress => 'Copy address';

  @override
  String httpAddressCopied(String url) {
    return 'Copied $url';
  }

  @override
  String get httpReasonAborted => 'The connection was dropped or aborted';

  @override
  String get httpReasonIo => 'Could not read or write the file';

  @override
  String get httpReasonDiskFull => 'The disk is full';

  @override
  String get httpReasonBlocked =>
      'The path is outside the root folder or not allowed';

  @override
  String httpReasonStatus(int status) {
    return 'Reply code $status';
  }

  @override
  String logHttpStarted(String address, int port, String root) {
    return 'HTTP server started on $address:$port · $root';
  }

  @override
  String get logHttpStopped => 'HTTP server stopped';

  @override
  String logHttpRequest(
    String method,
    String path,
    int status,
    String client,
    String bytes,
    String seconds,
    String rate,
  ) {
    return '$method $path → $status ($client) · $bytes · ${seconds}s · $rate';
  }

  @override
  String logHttpAborted(
    String method,
    String path,
    String client,
    String bytes,
  ) {
    return '$method $path aborted ($client) · sent $bytes';
  }

  @override
  String logHttpBlocked(String path, String client, String reason) {
    return 'Blocked a path that is not allowed: $path ($client, $reason)';
  }

  @override
  String logHttpBusy(String client, int limit) {
    return 'Too many concurrent requests, refused ($client, max $limit)';
  }

  @override
  String logHttpConnectionError(String error) {
    return 'Connection error: $error';
  }

  @override
  String logHttpPortInUse(String address, int port, String error) {
    return '$address:$port is already used by another program: $error';
  }

  @override
  String logHttpPermissionDenied(String address, int port, String error) {
    return 'No permission to open $address:$port: $error';
  }

  @override
  String logHttpBindFailed(String address, int port, String error) {
    return 'Could not open $address:$port: $error';
  }
}
