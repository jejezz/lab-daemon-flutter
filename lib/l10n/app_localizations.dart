import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ko'),
  ];

  /// No description provided for @aboutTooltip.
  ///
  /// In ko, this message translates to:
  /// **'정보'**
  String get aboutTooltip;

  /// No description provided for @aboutVersion.
  ///
  /// In ko, this message translates to:
  /// **'버전 {version} (빌드 {build})'**
  String aboutVersion(String version, String build);

  /// No description provided for @aboutOpenSourceLicenses.
  ///
  /// In ko, this message translates to:
  /// **'오픈소스 라이선스'**
  String get aboutOpenSourceLicenses;

  /// No description provided for @aboutRepository.
  ///
  /// In ko, this message translates to:
  /// **'GitHub'**
  String get aboutRepository;

  /// No description provided for @commonClose.
  ///
  /// In ko, this message translates to:
  /// **'닫기'**
  String get commonClose;

  /// No description provided for @aboutMenuItem.
  ///
  /// In ko, this message translates to:
  /// **'{appName} 정보'**
  String aboutMenuItem(String appName);

  /// No description provided for @themeSystem.
  ///
  /// In ko, this message translates to:
  /// **'시스템 설정 따르기'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In ko, this message translates to:
  /// **'라이트'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In ko, this message translates to:
  /// **'다크'**
  String get themeDark;

  /// No description provided for @languageSystemShort.
  ///
  /// In ko, this message translates to:
  /// **'시스템'**
  String get languageSystemShort;

  /// No description provided for @settingsTooltip.
  ///
  /// In ko, this message translates to:
  /// **'설정'**
  String get settingsTooltip;

  /// No description provided for @settingsTitle.
  ///
  /// In ko, this message translates to:
  /// **'설정'**
  String get settingsTitle;

  /// No description provided for @settingsSectionAppearance.
  ///
  /// In ko, this message translates to:
  /// **'외형'**
  String get settingsSectionAppearance;

  /// No description provided for @settingsLanguage.
  ///
  /// In ko, this message translates to:
  /// **'언어'**
  String get settingsLanguage;

  /// No description provided for @settingsMode.
  ///
  /// In ko, this message translates to:
  /// **'모드'**
  String get settingsMode;

  /// No description provided for @settingsModeSystem.
  ///
  /// In ko, this message translates to:
  /// **'시스템'**
  String get settingsModeSystem;

  /// No description provided for @settingsPalette.
  ///
  /// In ko, this message translates to:
  /// **'색 구성'**
  String get settingsPalette;

  /// No description provided for @settingsPaletteSaturn.
  ///
  /// In ko, this message translates to:
  /// **'새턴'**
  String get settingsPaletteSaturn;

  /// No description provided for @settingsPaletteTeal.
  ///
  /// In ko, this message translates to:
  /// **'청록'**
  String get settingsPaletteTeal;

  /// No description provided for @settingsPaletteAmber.
  ///
  /// In ko, this message translates to:
  /// **'호박'**
  String get settingsPaletteAmber;

  /// No description provided for @settingsPaletteRose.
  ///
  /// In ko, this message translates to:
  /// **'장미'**
  String get settingsPaletteRose;

  /// No description provided for @settingsPaletteSlate.
  ///
  /// In ko, this message translates to:
  /// **'슬레이트'**
  String get settingsPaletteSlate;

  /// No description provided for @settingsPaletteHighContrast.
  ///
  /// In ko, this message translates to:
  /// **'고대비'**
  String get settingsPaletteHighContrast;

  /// No description provided for @aboutTagline.
  ///
  /// In ko, this message translates to:
  /// **'랩용 네트워크 서비스를 한 곳에서 켜고 지켜봅니다'**
  String get aboutTagline;

  /// No description provided for @aboutDescription.
  ///
  /// In ko, this message translates to:
  /// **'DHCP, TFTP, FTP 서버를 켜고 접속 현황과 로그를 실시간으로 확인합니다. 보드 플래싱과 랩 환경에서 쓰는 간이 서버 모음입니다.'**
  String get aboutDescription;

  /// No description provided for @homeEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'서비스가 꺼져 있어요'**
  String get homeEmptyTitle;

  /// No description provided for @homeEmptyAction.
  ///
  /// In ko, this message translates to:
  /// **'서비스 시작'**
  String get homeEmptyAction;

  /// No description provided for @updateCheckMenuItem.
  ///
  /// In ko, this message translates to:
  /// **'업데이트 확인'**
  String get updateCheckMenuItem;

  /// No description provided for @updateChecking.
  ///
  /// In ko, this message translates to:
  /// **'업데이트를 확인하는 중…'**
  String get updateChecking;

  /// No description provided for @updateAvailableTitle.
  ///
  /// In ko, this message translates to:
  /// **'새 버전이 있습니다'**
  String get updateAvailableTitle;

  /// No description provided for @updateAvailableBody.
  ///
  /// In ko, this message translates to:
  /// **'{appName} {latest} 버전이 나왔습니다. (현재 {current})'**
  String updateAvailableBody(String appName, String current, String latest);

  /// No description provided for @updateReleaseNotes.
  ///
  /// In ko, this message translates to:
  /// **'변경 내용'**
  String get updateReleaseNotes;

  /// No description provided for @updateNow.
  ///
  /// In ko, this message translates to:
  /// **'지금 업데이트'**
  String get updateNow;

  /// No description provided for @updateLater.
  ///
  /// In ko, this message translates to:
  /// **'나중에'**
  String get updateLater;

  /// No description provided for @updateSkipVersion.
  ///
  /// In ko, this message translates to:
  /// **'이 버전 건너뛰기'**
  String get updateSkipVersion;

  /// No description provided for @updateDownloading.
  ///
  /// In ko, this message translates to:
  /// **'내려받는 중…'**
  String get updateDownloading;

  /// No description provided for @updateVerifying.
  ///
  /// In ko, this message translates to:
  /// **'파일을 확인하는 중…'**
  String get updateVerifying;

  /// No description provided for @updateDownloadProgress.
  ///
  /// In ko, this message translates to:
  /// **'{received} / {total}'**
  String updateDownloadProgress(String received, String total);

  /// No description provided for @updateCancel.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get updateCancel;

  /// No description provided for @updateFailedTitle.
  ///
  /// In ko, this message translates to:
  /// **'업데이트하지 못했습니다'**
  String get updateFailedTitle;

  /// No description provided for @updateCheckFailedTitle.
  ///
  /// In ko, this message translates to:
  /// **'업데이트를 확인하지 못했습니다'**
  String get updateCheckFailedTitle;

  /// No description provided for @updateErrorNetwork.
  ///
  /// In ko, this message translates to:
  /// **'업데이트 서버에 연결하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도해 주세요.'**
  String get updateErrorNetwork;

  /// No description provided for @updateErrorChecksum.
  ///
  /// In ko, this message translates to:
  /// **'내려받은 파일이 올바르지 않아 설치하지 않았습니다. 잠시 뒤에 다시 시도해 주세요.'**
  String get updateErrorChecksum;

  /// No description provided for @updateErrorInstall.
  ///
  /// In ko, this message translates to:
  /// **'설치를 시작하지 못했습니다.'**
  String get updateErrorInstall;

  /// No description provided for @updateErrorGeneric.
  ///
  /// In ko, this message translates to:
  /// **'업데이트 서버에서 예상하지 못한 응답을 받았습니다. 잠시 뒤에 다시 시도해 주세요.'**
  String get updateErrorGeneric;

  /// No description provided for @updateUpToDateTitle.
  ///
  /// In ko, this message translates to:
  /// **'최신 버전입니다'**
  String get updateUpToDateTitle;

  /// No description provided for @updateUpToDateBody.
  ///
  /// In ko, this message translates to:
  /// **'{version} 버전을 사용 중입니다.'**
  String updateUpToDateBody(String version);

  /// No description provided for @updateUnavailableTitle.
  ///
  /// In ko, this message translates to:
  /// **'직접 설치해 주세요'**
  String get updateUnavailableTitle;

  /// No description provided for @updateUnavailableBody.
  ///
  /// In ko, this message translates to:
  /// **'{latest} 버전이 있지만 앱에서 자동으로 설치할 수 없습니다. 릴리스 페이지에서 받아 주세요.'**
  String updateUnavailableBody(String latest);

  /// No description provided for @updateOpenReleasePage.
  ///
  /// In ko, this message translates to:
  /// **'릴리스 페이지 열기'**
  String get updateOpenReleasePage;

  /// No description provided for @updateBrowserDownloadTitle.
  ///
  /// In ko, this message translates to:
  /// **'브라우저에서 내려받습니다'**
  String get updateBrowserDownloadTitle;

  /// No description provided for @updateBrowserDownloadBody.
  ///
  /// In ko, this message translates to:
  /// **'브라우저가 새 버전 내려받기를 시작합니다. 받은 DMG를 열어 {appName} 을(를) Applications 폴더로 끌어다 놓아 주세요. 실행 중이면 종료한 뒤 덮어쓰세요.'**
  String updateBrowserDownloadBody(String appName);

  /// No description provided for @updateMacosOpenedTitle.
  ///
  /// In ko, this message translates to:
  /// **'설치 창이 열렸습니다'**
  String get updateMacosOpenedTitle;

  /// No description provided for @updateMacosOpenedBody.
  ///
  /// In ko, this message translates to:
  /// **'열린 창에서 {appName} 을(를) Applications 폴더로 끌어다 놓아 주세요. 실행 중이면 종료한 뒤 덮어쓰세요.'**
  String updateMacosOpenedBody(String appName);

  /// No description provided for @updateWindowsInstallTitle.
  ///
  /// In ko, this message translates to:
  /// **'설치 프로그램을 열었습니다'**
  String get updateWindowsInstallTitle;

  /// No description provided for @updateWindowsInstallBody.
  ///
  /// In ko, this message translates to:
  /// **'설치하려면 {appName} 을(를) 종료해야 합니다. 설치 프로그램의 안내를 따라 주세요.'**
  String updateWindowsInstallBody(String appName);

  /// No description provided for @updateQuitApp.
  ///
  /// In ko, this message translates to:
  /// **'{appName} 종료'**
  String updateQuitApp(String appName);

  /// No description provided for @updateLinuxInstallTitle.
  ///
  /// In ko, this message translates to:
  /// **'설치를 준비했습니다'**
  String get updateLinuxInstallTitle;

  /// No description provided for @updateLinuxInstallBody.
  ///
  /// In ko, this message translates to:
  /// **'{appName} 을(를) 종료하고 설치합니다. 설치가 끝나면 자동으로 다시 시작됩니다.'**
  String updateLinuxInstallBody(String appName);

  /// No description provided for @updateQuitAndInstall.
  ///
  /// In ko, this message translates to:
  /// **'종료하고 설치'**
  String get updateQuitAndInstall;

  /// No description provided for @updateBusyTitle.
  ///
  /// In ko, this message translates to:
  /// **'지금은 업데이트할 수 없습니다'**
  String get updateBusyTitle;

  /// No description provided for @updateBusyBody.
  ///
  /// In ko, this message translates to:
  /// **'작업이 진행 중입니다. 끝난 뒤에 다시 시도해 주세요.'**
  String get updateBusyBody;

  /// No description provided for @servicesTitle.
  ///
  /// In ko, this message translates to:
  /// **'서비스'**
  String get servicesTitle;

  /// No description provided for @serviceDhcp.
  ///
  /// In ko, this message translates to:
  /// **'DHCP'**
  String get serviceDhcp;

  /// No description provided for @serviceStartTooltip.
  ///
  /// In ko, this message translates to:
  /// **'서비스 시작'**
  String get serviceStartTooltip;

  /// No description provided for @serviceStopTooltip.
  ///
  /// In ko, this message translates to:
  /// **'서비스 중지'**
  String get serviceStopTooltip;

  /// No description provided for @stateStopped.
  ///
  /// In ko, this message translates to:
  /// **'중지됨'**
  String get stateStopped;

  /// No description provided for @stateStarting.
  ///
  /// In ko, this message translates to:
  /// **'시작 중'**
  String get stateStarting;

  /// No description provided for @stateRunning.
  ///
  /// In ko, this message translates to:
  /// **'실행 중'**
  String get stateRunning;

  /// No description provided for @stateStopping.
  ///
  /// In ko, this message translates to:
  /// **'중지 중'**
  String get stateStopping;

  /// No description provided for @stateError.
  ///
  /// In ko, this message translates to:
  /// **'오류'**
  String get stateError;

  /// No description provided for @statusServer.
  ///
  /// In ko, this message translates to:
  /// **'서버'**
  String get statusServer;

  /// No description provided for @statusPool.
  ///
  /// In ko, this message translates to:
  /// **'범위'**
  String get statusPool;

  /// No description provided for @statusGateway.
  ///
  /// In ko, this message translates to:
  /// **'게이트웨이'**
  String get statusGateway;

  /// No description provided for @statusLeaseTime.
  ///
  /// In ko, this message translates to:
  /// **'Lease Time'**
  String get statusLeaseTime;

  /// No description provided for @statusUsage.
  ///
  /// In ko, this message translates to:
  /// **'사용 {used}/{total}'**
  String statusUsage(int used, int total);

  /// No description provided for @statusUptime.
  ///
  /// In ko, this message translates to:
  /// **'가동 {time}'**
  String statusUptime(String time);

  /// No description provided for @statsLine.
  ///
  /// In ko, this message translates to:
  /// **'Discover {discover} · Offer {offer} · Request {request} · ACK {ack} · NAK {nak}'**
  String statsLine(int discover, int offer, int request, int ack, int nak);

  /// No description provided for @leaseColIp.
  ///
  /// In ko, this message translates to:
  /// **'IP 주소'**
  String get leaseColIp;

  /// No description provided for @leaseColMac.
  ///
  /// In ko, this message translates to:
  /// **'MAC 주소'**
  String get leaseColMac;

  /// No description provided for @leaseColHostname.
  ///
  /// In ko, this message translates to:
  /// **'호스트 이름'**
  String get leaseColHostname;

  /// No description provided for @leaseColState.
  ///
  /// In ko, this message translates to:
  /// **'상태'**
  String get leaseColState;

  /// No description provided for @leaseColRemaining.
  ///
  /// In ko, this message translates to:
  /// **'남은 시간'**
  String get leaseColRemaining;

  /// No description provided for @leaseStateOffered.
  ///
  /// In ko, this message translates to:
  /// **'제안됨'**
  String get leaseStateOffered;

  /// No description provided for @leaseStateBound.
  ///
  /// In ko, this message translates to:
  /// **'사용 중'**
  String get leaseStateBound;

  /// No description provided for @leaseUnlimited.
  ///
  /// In ko, this message translates to:
  /// **'무제한'**
  String get leaseUnlimited;

  /// No description provided for @leaseRelease.
  ///
  /// In ko, this message translates to:
  /// **'해제'**
  String get leaseRelease;

  /// No description provided for @leaseReleaseAll.
  ///
  /// In ko, this message translates to:
  /// **'전체 해제'**
  String get leaseReleaseAll;

  /// No description provided for @leaseReleaseAllConfirmTitle.
  ///
  /// In ko, this message translates to:
  /// **'모든 Lease를 해제할까요?'**
  String get leaseReleaseAllConfirmTitle;

  /// No description provided for @leaseReleaseAllConfirmBody.
  ///
  /// In ko, this message translates to:
  /// **'{count}개의 Lease를 해제해요. 장비는 다음 갱신 때 새 주소를 받아요.'**
  String leaseReleaseAllConfirmBody(int count);

  /// No description provided for @leaseReleasedSnack.
  ///
  /// In ko, this message translates to:
  /// **'{ip}를 해제했어요'**
  String leaseReleasedSnack(String ip);

  /// No description provided for @leaseReleasedAllSnack.
  ///
  /// In ko, this message translates to:
  /// **'Lease {count}개를 해제했어요'**
  String leaseReleasedAllSnack(int count);

  /// No description provided for @leaseEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'아직 Lease가 없어요'**
  String get leaseEmptyTitle;

  /// No description provided for @leaseEmptyHint.
  ///
  /// In ko, this message translates to:
  /// **'장비가 DHCP로 주소를 요청하면 여기에 나타나요'**
  String get leaseEmptyHint;

  /// No description provided for @startFailed.
  ///
  /// In ko, this message translates to:
  /// **'서비스를 시작하지 못했어요: {error}'**
  String startFailed(String error);

  /// No description provided for @errorCopy.
  ///
  /// In ko, this message translates to:
  /// **'복사'**
  String get errorCopy;

  /// No description provided for @logTitle.
  ///
  /// In ko, this message translates to:
  /// **'로그'**
  String get logTitle;

  /// No description provided for @logLevelDebug.
  ///
  /// In ko, this message translates to:
  /// **'디버그'**
  String get logLevelDebug;

  /// No description provided for @logLevelInfo.
  ///
  /// In ko, this message translates to:
  /// **'정보'**
  String get logLevelInfo;

  /// No description provided for @logLevelWarning.
  ///
  /// In ko, this message translates to:
  /// **'경고'**
  String get logLevelWarning;

  /// No description provided for @logLevelError.
  ///
  /// In ko, this message translates to:
  /// **'오류'**
  String get logLevelError;

  /// No description provided for @logSearchHint.
  ///
  /// In ko, this message translates to:
  /// **'로그 검색'**
  String get logSearchHint;

  /// No description provided for @logPause.
  ///
  /// In ko, this message translates to:
  /// **'일시정지'**
  String get logPause;

  /// No description provided for @logResume.
  ///
  /// In ko, this message translates to:
  /// **'계속'**
  String get logResume;

  /// No description provided for @logClear.
  ///
  /// In ko, this message translates to:
  /// **'지우기'**
  String get logClear;

  /// No description provided for @logCopy.
  ///
  /// In ko, this message translates to:
  /// **'복사'**
  String get logCopy;

  /// No description provided for @logCopied.
  ///
  /// In ko, this message translates to:
  /// **'로그를 복사했어요'**
  String get logCopied;

  /// No description provided for @logEmpty.
  ///
  /// In ko, this message translates to:
  /// **'표시할 로그가 없어요'**
  String get logEmpty;

  /// No description provided for @logPausedBanner.
  ///
  /// In ko, this message translates to:
  /// **'일시정지됨 · 새 로그 {count}개'**
  String logPausedBanner(int count);

  /// No description provided for @dhcpFieldServerIp.
  ///
  /// In ko, this message translates to:
  /// **'서버 NIC'**
  String get dhcpFieldServerIp;

  /// No description provided for @dhcpFieldRangeStart.
  ///
  /// In ko, this message translates to:
  /// **'시작 주소'**
  String get dhcpFieldRangeStart;

  /// No description provided for @dhcpFieldRangeEnd.
  ///
  /// In ko, this message translates to:
  /// **'끝 주소'**
  String get dhcpFieldRangeEnd;

  /// No description provided for @dhcpFieldMask.
  ///
  /// In ko, this message translates to:
  /// **'서브넷 마스크'**
  String get dhcpFieldMask;

  /// No description provided for @dhcpFieldGateway.
  ///
  /// In ko, this message translates to:
  /// **'게이트웨이'**
  String get dhcpFieldGateway;

  /// No description provided for @dhcpFieldDns.
  ///
  /// In ko, this message translates to:
  /// **'DNS 서버'**
  String get dhcpFieldDns;

  /// No description provided for @dhcpFieldLeaseTime.
  ///
  /// In ko, this message translates to:
  /// **'Lease Time'**
  String get dhcpFieldLeaseTime;

  /// No description provided for @dhcpFieldDomain.
  ///
  /// In ko, this message translates to:
  /// **'도메인 이름'**
  String get dhcpFieldDomain;

  /// No description provided for @dhcpFieldTftp.
  ///
  /// In ko, this message translates to:
  /// **'TFTP 서버'**
  String get dhcpFieldTftp;

  /// No description provided for @dhcpFieldBootFile.
  ///
  /// In ko, this message translates to:
  /// **'부팅 파일'**
  String get dhcpFieldBootFile;

  /// No description provided for @dhcpHintDns.
  ///
  /// In ko, this message translates to:
  /// **'쉼표로 구분'**
  String get dhcpHintDns;

  /// No description provided for @dhcpHintLeaseTime.
  ///
  /// In ko, this message translates to:
  /// **'예: 30s, 10m, 12h, 1d, infinite'**
  String get dhcpHintLeaseTime;

  /// No description provided for @dhcpHintOptional.
  ///
  /// In ko, this message translates to:
  /// **'선택'**
  String get dhcpHintOptional;

  /// No description provided for @dhcpDirectedBroadcast.
  ///
  /// In ko, this message translates to:
  /// **'서브넷 브로드캐스트로 응답'**
  String get dhcpDirectedBroadcast;

  /// No description provided for @dhcpDirectedBroadcastHint.
  ///
  /// In ko, this message translates to:
  /// **'응답이 엉뚱한 NIC로 나갈 때만 켜세요'**
  String get dhcpDirectedBroadcastHint;

  /// No description provided for @dhcpLogPackets.
  ///
  /// In ko, this message translates to:
  /// **'패킷 16진수 덤프를 디버그 로그에 기록'**
  String get dhcpLogPackets;

  /// No description provided for @dhcpRestartNote.
  ///
  /// In ko, this message translates to:
  /// **'실행 중에는 Lease Time만 바로 적용돼요. 나머지는 서비스를 다시 시작하면 적용돼요.'**
  String get dhcpRestartNote;

  /// No description provided for @dhcpNicNone.
  ///
  /// In ko, this message translates to:
  /// **'NIC를 찾지 못했어요'**
  String get dhcpNicNone;

  /// No description provided for @dhcpNicRefresh.
  ///
  /// In ko, this message translates to:
  /// **'NIC 새로고침'**
  String get dhcpNicRefresh;

  /// No description provided for @dhcpNicMissing.
  ///
  /// In ko, this message translates to:
  /// **'{ip} (목록에 없음)'**
  String dhcpNicMissing(String ip);

  /// No description provided for @fieldErrRequired.
  ///
  /// In ko, this message translates to:
  /// **'값이 필요해요'**
  String get fieldErrRequired;

  /// No description provided for @fieldErrInvalidIp.
  ///
  /// In ko, this message translates to:
  /// **'올바른 IPv4 주소가 아니에요'**
  String get fieldErrInvalidIp;

  /// No description provided for @fieldErrInvalidMask.
  ///
  /// In ko, this message translates to:
  /// **'올바른 서브넷 마스크가 아니에요'**
  String get fieldErrInvalidMask;

  /// No description provided for @fieldErrInvalidLeaseTime.
  ///
  /// In ko, this message translates to:
  /// **'30s, 10m, 12h, 1d, infinite 중 하나여야 해요'**
  String get fieldErrInvalidLeaseTime;

  /// No description provided for @fieldErrNotInSubnet.
  ///
  /// In ko, this message translates to:
  /// **'서브넷 밖의 주소예요'**
  String get fieldErrNotInSubnet;

  /// No description provided for @fieldErrNotHost.
  ///
  /// In ko, this message translates to:
  /// **'네트워크·브로드캐스트 주소는 쓸 수 없어요'**
  String get fieldErrNotHost;

  /// No description provided for @fieldErrRangeReversed.
  ///
  /// In ko, this message translates to:
  /// **'시작 주소보다 앞서요'**
  String get fieldErrRangeReversed;

  /// No description provided for @fieldErrTooLong.
  ///
  /// In ko, this message translates to:
  /// **'너무 길어요'**
  String get fieldErrTooLong;

  /// No description provided for @nakReasonWrongNetwork.
  ///
  /// In ko, this message translates to:
  /// **'다른 네트워크의 주소'**
  String get nakReasonWrongNetwork;

  /// No description provided for @nakReasonAddressUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'줄 수 없는 주소'**
  String get nakReasonAddressUnavailable;

  /// No description provided for @logDhcpDiscover.
  ///
  /// In ko, this message translates to:
  /// **'DISCOVER {mac} {hostname}'**
  String logDhcpDiscover(String mac, String hostname);

  /// No description provided for @logDhcpOffer.
  ///
  /// In ko, this message translates to:
  /// **'OFFER {ip} → {mac}'**
  String logDhcpOffer(String ip, String mac);

  /// No description provided for @logDhcpRequest.
  ///
  /// In ko, this message translates to:
  /// **'REQUEST {ip} ← {mac} {hostname}'**
  String logDhcpRequest(String ip, String mac, String hostname);

  /// No description provided for @logDhcpAck.
  ///
  /// In ko, this message translates to:
  /// **'ACK {ip} → {mac} (Lease {lease})'**
  String logDhcpAck(String ip, String mac, String lease);

  /// No description provided for @logDhcpNak.
  ///
  /// In ko, this message translates to:
  /// **'NAK {ip} → {mac}: {reason}'**
  String logDhcpNak(String ip, String mac, String reason);

  /// No description provided for @logDhcpRelease.
  ///
  /// In ko, this message translates to:
  /// **'RELEASE {ip} ← {mac}'**
  String logDhcpRelease(String ip, String mac);

  /// No description provided for @logDhcpDecline.
  ///
  /// In ko, this message translates to:
  /// **'DECLINE {ip} ← {mac}: 클라이언트가 주소 충돌을 알렸어요'**
  String logDhcpDecline(String ip, String mac);

  /// No description provided for @logDhcpInform.
  ///
  /// In ko, this message translates to:
  /// **'INFORM {ip} ← {mac}'**
  String logDhcpInform(String ip, String mac);

  /// No description provided for @logDhcpPoolExhausted.
  ///
  /// In ko, this message translates to:
  /// **'{mac}에 줄 주소가 없어요 (풀이 가득 찼어요)'**
  String logDhcpPoolExhausted(String mac);

  /// No description provided for @logDhcpOtherServer.
  ///
  /// In ko, this message translates to:
  /// **'{mac}이(가) 다른 서버 {server}를 골랐어요'**
  String logDhcpOtherServer(String mac, String server);

  /// No description provided for @logDhcpIgnored.
  ///
  /// In ko, this message translates to:
  /// **'무시한 패킷: {reason}'**
  String logDhcpIgnored(String reason);

  /// No description provided for @logDhcpMalformed.
  ///
  /// In ko, this message translates to:
  /// **'{from}에서 온 잘못된 패킷: {error}'**
  String logDhcpMalformed(String from, String error);

  /// No description provided for @logDhcpStarted.
  ///
  /// In ko, this message translates to:
  /// **'DHCP 서버 시작 {address} · {start} ~ {end} · {mask}'**
  String logDhcpStarted(String address, String start, String end, String mask);

  /// No description provided for @logDhcpStopped.
  ///
  /// In ko, this message translates to:
  /// **'DHCP 서버를 중지했어요'**
  String get logDhcpStopped;

  /// No description provided for @logDhcpExpired.
  ///
  /// In ko, this message translates to:
  /// **'Lease 만료 {ip} ({mac})'**
  String logDhcpExpired(String ip, String mac);

  /// No description provided for @logDhcpManualRelease.
  ///
  /// In ko, this message translates to:
  /// **'Lease 해제 {ip} ({mac})'**
  String logDhcpManualRelease(String ip, String mac);

  /// No description provided for @logDhcpReserved.
  ///
  /// In ko, this message translates to:
  /// **'예약 추가 {mac} = {ip}'**
  String logDhcpReserved(String mac, String ip);

  /// No description provided for @logDhcpUnreserved.
  ///
  /// In ko, this message translates to:
  /// **'예약 삭제 {mac}'**
  String logDhcpUnreserved(String mac);

  /// No description provided for @logDhcpPortInUse.
  ///
  /// In ko, this message translates to:
  /// **'{address}:{port}를 다른 프로그램이 쓰고 있어요: {error}'**
  String logDhcpPortInUse(String address, int port, String error);

  /// No description provided for @logDhcpPermissionDenied.
  ///
  /// In ko, this message translates to:
  /// **'{address}:{port}를 열 권한이 없어요: {error}'**
  String logDhcpPermissionDenied(String address, int port, String error);

  /// No description provided for @logDhcpBindFailed.
  ///
  /// In ko, this message translates to:
  /// **'{address}:{port}를 열지 못했어요: {error}'**
  String logDhcpBindFailed(String address, int port, String error);

  /// No description provided for @logDhcpSendFailed.
  ///
  /// In ko, this message translates to:
  /// **'{to}로 응답을 보내지 못했어요: {error}'**
  String logDhcpSendFailed(String to, String error);

  /// No description provided for @logDhcpPacketIn.
  ///
  /// In ko, this message translates to:
  /// **'수신 {from}'**
  String logDhcpPacketIn(String from);

  /// No description provided for @logDhcpPacketOut.
  ///
  /// In ko, this message translates to:
  /// **'송신 {to}:{port}'**
  String logDhcpPacketOut(String to, int port);

  /// No description provided for @commonCancel.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get commonCancel;

  /// No description provided for @stateChecking.
  ///
  /// In ko, this message translates to:
  /// **'확인 중'**
  String get stateChecking;

  /// No description provided for @probeConflictTitle.
  ///
  /// In ko, this message translates to:
  /// **'같은 망에 다른 DHCP 서버가 있어요'**
  String get probeConflictTitle;

  /// No description provided for @probeConflictBody.
  ///
  /// In ko, this message translates to:
  /// **'선택한 NIC에서 아래 서버가 응답했어요. 서버 두 대가 같은 망에서 주소를 나눠 주면 장비가 엉뚱한 주소를 받거나 연결이 불안정해질 수 있어요.'**
  String get probeConflictBody;

  /// No description provided for @probeServerLine.
  ///
  /// In ko, this message translates to:
  /// **'{server} (제안 {offered})'**
  String probeServerLine(String server, String offered);

  /// No description provided for @probeConflictAdvice.
  ///
  /// In ko, this message translates to:
  /// **'장비를 이 PC에 직접 연결한 격리된 망이 맞는지 확인하세요. 회사나 집 공유기가 있는 망이라면 켜지 않는 것이 안전해요.'**
  String get probeConflictAdvice;

  /// No description provided for @probeStartAnyway.
  ///
  /// In ko, this message translates to:
  /// **'그래도 시작'**
  String get probeStartAnyway;

  /// No description provided for @dhcpDetectOthers.
  ///
  /// In ko, this message translates to:
  /// **'시작하기 전에 다른 DHCP 서버 확인'**
  String get dhcpDetectOthers;

  /// No description provided for @dhcpDetectOthersHint.
  ///
  /// In ko, this message translates to:
  /// **'같은 망에서 응답하는 서버가 있으면 경고해요 (약 3초)'**
  String get dhcpDetectOthersHint;

  /// No description provided for @logDhcpProbeStart.
  ///
  /// In ko, this message translates to:
  /// **'다른 DHCP 서버 확인 중 ({address})'**
  String logDhcpProbeStart(String address);

  /// No description provided for @logDhcpProbeNone.
  ///
  /// In ko, this message translates to:
  /// **'다른 DHCP 서버의 응답이 없었어요'**
  String get logDhcpProbeNone;

  /// No description provided for @logDhcpProbeFailed.
  ///
  /// In ko, this message translates to:
  /// **'다른 DHCP 서버를 확인하지 못했어요: {error}'**
  String logDhcpProbeFailed(String error);

  /// No description provided for @serviceTftp.
  ///
  /// In ko, this message translates to:
  /// **'TFTP'**
  String get serviceTftp;

  /// No description provided for @serviceFtp.
  ///
  /// In ko, this message translates to:
  /// **'FTP'**
  String get serviceFtp;

  /// No description provided for @panelToggleTooltip.
  ///
  /// In ko, this message translates to:
  /// **'설정 패널 보이기/숨기기'**
  String get panelToggleTooltip;

  /// No description provided for @panelTitle.
  ///
  /// In ko, this message translates to:
  /// **'{service} 설정'**
  String panelTitle(String service);

  /// No description provided for @runningLockedNote.
  ///
  /// In ko, this message translates to:
  /// **'실행 중에는 설정을 바꿀 수 없어요. 서비스를 멈추고 바꾸세요.'**
  String get runningLockedNote;

  /// No description provided for @fieldBindNic.
  ///
  /// In ko, this message translates to:
  /// **'사용할 NIC'**
  String get fieldBindNic;

  /// No description provided for @fieldAllNics.
  ///
  /// In ko, this message translates to:
  /// **'모든 NIC (0.0.0.0)'**
  String get fieldAllNics;

  /// No description provided for @fieldAllNicsWarning.
  ///
  /// In ko, this message translates to:
  /// **'모든 NIC에서 받아요. 회사망 쪽에도 열릴 수 있어요.'**
  String get fieldAllNicsWarning;

  /// No description provided for @fieldPort.
  ///
  /// In ko, this message translates to:
  /// **'포트'**
  String get fieldPort;

  /// No description provided for @fieldRootDir.
  ///
  /// In ko, this message translates to:
  /// **'루트 폴더'**
  String get fieldRootDir;

  /// No description provided for @fieldBrowse.
  ///
  /// In ko, this message translates to:
  /// **'찾아보기'**
  String get fieldBrowse;

  /// No description provided for @sectionAdvanced.
  ///
  /// In ko, this message translates to:
  /// **'고급'**
  String get sectionAdvanced;

  /// No description provided for @fieldErrDirMissing.
  ///
  /// In ko, this message translates to:
  /// **'폴더가 없어요'**
  String get fieldErrDirMissing;

  /// No description provided for @fieldErrInvalidPort.
  ///
  /// In ko, this message translates to:
  /// **'1~65535 사이여야 해요'**
  String get fieldErrInvalidPort;

  /// No description provided for @fieldErrInvalidNumber.
  ///
  /// In ko, this message translates to:
  /// **'허용 범위 밖의 숫자예요'**
  String get fieldErrInvalidNumber;

  /// No description provided for @startInvalidSettingsFor.
  ///
  /// In ko, this message translates to:
  /// **'{service} 설정이 올바르지 않아요. 왼쪽 설정을 확인해 주세요.'**
  String startInvalidSettingsFor(String service);

  /// No description provided for @tftpAllowWrite.
  ///
  /// In ko, this message translates to:
  /// **'업로드 허용'**
  String get tftpAllowWrite;

  /// No description provided for @tftpAllowWriteHint.
  ///
  /// In ko, this message translates to:
  /// **'클라이언트가 루트 폴더에 파일을 올릴 수 있어요'**
  String get tftpAllowWriteHint;

  /// No description provided for @tftpAllowOverwrite.
  ///
  /// In ko, this message translates to:
  /// **'기존 파일 덮어쓰기 허용'**
  String get tftpAllowOverwrite;

  /// No description provided for @tftpMaxBlockSize.
  ///
  /// In ko, this message translates to:
  /// **'최대 블록 크기 (바이트)'**
  String get tftpMaxBlockSize;

  /// No description provided for @tftpMaxWindow.
  ///
  /// In ko, this message translates to:
  /// **'최대 윈도우 (블록)'**
  String get tftpMaxWindow;

  /// No description provided for @tftpTimeout.
  ///
  /// In ko, this message translates to:
  /// **'재전송 대기 (ms)'**
  String get tftpTimeout;

  /// No description provided for @tftpMaxTransfers.
  ///
  /// In ko, this message translates to:
  /// **'동시 전송 수'**
  String get tftpMaxTransfers;

  /// No description provided for @tftpLogPackets.
  ///
  /// In ko, this message translates to:
  /// **'요청 패킷 덤프를 디버그 로그에 기록'**
  String get tftpLogPackets;

  /// No description provided for @tftpColClient.
  ///
  /// In ko, this message translates to:
  /// **'클라이언트'**
  String get tftpColClient;

  /// No description provided for @tftpColFile.
  ///
  /// In ko, this message translates to:
  /// **'파일'**
  String get tftpColFile;

  /// No description provided for @tftpColDirection.
  ///
  /// In ko, this message translates to:
  /// **'방향'**
  String get tftpColDirection;

  /// No description provided for @tftpColProgress.
  ///
  /// In ko, this message translates to:
  /// **'진행'**
  String get tftpColProgress;

  /// No description provided for @tftpColRate.
  ///
  /// In ko, this message translates to:
  /// **'속도'**
  String get tftpColRate;

  /// No description provided for @tftpColState.
  ///
  /// In ko, this message translates to:
  /// **'상태'**
  String get tftpColState;

  /// No description provided for @tftpDownload.
  ///
  /// In ko, this message translates to:
  /// **'보냄'**
  String get tftpDownload;

  /// No description provided for @tftpUpload.
  ///
  /// In ko, this message translates to:
  /// **'받음'**
  String get tftpUpload;

  /// No description provided for @tftpStateActive.
  ///
  /// In ko, this message translates to:
  /// **'진행 중'**
  String get tftpStateActive;

  /// No description provided for @tftpStateDone.
  ///
  /// In ko, this message translates to:
  /// **'완료'**
  String get tftpStateDone;

  /// No description provided for @tftpStateFailed.
  ///
  /// In ko, this message translates to:
  /// **'실패'**
  String get tftpStateFailed;

  /// No description provided for @tftpAbort.
  ///
  /// In ko, this message translates to:
  /// **'중단'**
  String get tftpAbort;

  /// No description provided for @tftpClearRecent.
  ///
  /// In ko, this message translates to:
  /// **'끝난 전송 지우기'**
  String get tftpClearRecent;

  /// No description provided for @tftpEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'아직 전송이 없어요'**
  String get tftpEmptyTitle;

  /// No description provided for @tftpEmptyHint.
  ///
  /// In ko, this message translates to:
  /// **'장비가 TFTP로 파일을 요청하면 여기에 나타나요'**
  String get tftpEmptyHint;

  /// No description provided for @tftpSummary.
  ///
  /// In ko, this message translates to:
  /// **'진행 {active} · 완료 {completed} · 실패 {failed} · 보냄 {sent} · 받음 {received}'**
  String tftpSummary(
    int active,
    int completed,
    int failed,
    String sent,
    String received,
  );

  /// No description provided for @tftpReasonNotFound.
  ///
  /// In ko, this message translates to:
  /// **'파일 없음'**
  String get tftpReasonNotFound;

  /// No description provided for @tftpReasonAccessViolation.
  ///
  /// In ko, this message translates to:
  /// **'접근 거부'**
  String get tftpReasonAccessViolation;

  /// No description provided for @tftpReasonFileExists.
  ///
  /// In ko, this message translates to:
  /// **'이미 있는 파일'**
  String get tftpReasonFileExists;

  /// No description provided for @tftpReasonWriteDisabled.
  ///
  /// In ko, this message translates to:
  /// **'업로드 꺼짐'**
  String get tftpReasonWriteDisabled;

  /// No description provided for @tftpReasonTimeout.
  ///
  /// In ko, this message translates to:
  /// **'응답 없음'**
  String get tftpReasonTimeout;

  /// No description provided for @tftpReasonClientError.
  ///
  /// In ko, this message translates to:
  /// **'클라이언트가 중단'**
  String get tftpReasonClientError;

  /// No description provided for @tftpReasonAborted.
  ///
  /// In ko, this message translates to:
  /// **'사용자가 중단'**
  String get tftpReasonAborted;

  /// No description provided for @tftpReasonDiskFull.
  ///
  /// In ko, this message translates to:
  /// **'디스크 가득 참'**
  String get tftpReasonDiskFull;

  /// No description provided for @tftpReasonIo.
  ///
  /// In ko, this message translates to:
  /// **'파일 입출력 오류'**
  String get tftpReasonIo;

  /// No description provided for @tftpReasonUnsupportedMode.
  ///
  /// In ko, this message translates to:
  /// **'지원하지 않는 모드'**
  String get tftpReasonUnsupportedMode;

  /// No description provided for @ftpAccount.
  ///
  /// In ko, this message translates to:
  /// **'계정'**
  String get ftpAccount;

  /// No description provided for @ftpUsername.
  ///
  /// In ko, this message translates to:
  /// **'사용자 이름'**
  String get ftpUsername;

  /// No description provided for @ftpPassword.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호'**
  String get ftpPassword;

  /// No description provided for @ftpPasswordSet.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호가 설정돼 있어요. 바꾸려면 새로 입력하세요.'**
  String get ftpPasswordSet;

  /// No description provided for @ftpPasswordHint.
  ///
  /// In ko, this message translates to:
  /// **'입력하면 바로 해시로만 저장돼요'**
  String get ftpPasswordHint;

  /// No description provided for @ftpAllowAnonymous.
  ///
  /// In ko, this message translates to:
  /// **'익명(anonymous) 접속 허용'**
  String get ftpAllowAnonymous;

  /// No description provided for @ftpAllowWrite.
  ///
  /// In ko, this message translates to:
  /// **'쓰기 허용 (올리기·지우기·이름 바꾸기)'**
  String get ftpAllowWrite;

  /// No description provided for @ftpAnonymousWriteWarning.
  ///
  /// In ko, this message translates to:
  /// **'익명 사용자도 파일을 바꿀 수 있어요'**
  String get ftpAnonymousWriteWarning;

  /// No description provided for @ftpPassiveStart.
  ///
  /// In ko, this message translates to:
  /// **'패시브 포트 시작'**
  String get ftpPassiveStart;

  /// No description provided for @ftpPassiveEnd.
  ///
  /// In ko, this message translates to:
  /// **'패시브 포트 끝'**
  String get ftpPassiveEnd;

  /// No description provided for @ftpPassiveHint.
  ///
  /// In ko, this message translates to:
  /// **'방화벽에서 이 범위도 열려 있어야 해요'**
  String get ftpPassiveHint;

  /// No description provided for @ftpMaxConnections.
  ///
  /// In ko, this message translates to:
  /// **'동시 접속 수'**
  String get ftpMaxConnections;

  /// No description provided for @ftpIdleTimeout.
  ///
  /// In ko, this message translates to:
  /// **'유휴 시간 제한 (초)'**
  String get ftpIdleTimeout;

  /// No description provided for @ftpLogCommands.
  ///
  /// In ko, this message translates to:
  /// **'모든 명령을 디버그 로그에 기록 (비밀번호는 가림)'**
  String get ftpLogCommands;

  /// No description provided for @ftpColClient.
  ///
  /// In ko, this message translates to:
  /// **'클라이언트'**
  String get ftpColClient;

  /// No description provided for @ftpColUser.
  ///
  /// In ko, this message translates to:
  /// **'사용자'**
  String get ftpColUser;

  /// No description provided for @ftpColDir.
  ///
  /// In ko, this message translates to:
  /// **'폴더'**
  String get ftpColDir;

  /// No description provided for @ftpColActivity.
  ///
  /// In ko, this message translates to:
  /// **'활동'**
  String get ftpColActivity;

  /// No description provided for @ftpColTraffic.
  ///
  /// In ko, this message translates to:
  /// **'받음 / 보냄'**
  String get ftpColTraffic;

  /// No description provided for @ftpColConnected.
  ///
  /// In ko, this message translates to:
  /// **'접속'**
  String get ftpColConnected;

  /// No description provided for @ftpNotLoggedIn.
  ///
  /// In ko, this message translates to:
  /// **'로그인 전'**
  String get ftpNotLoggedIn;

  /// No description provided for @ftpDisconnect.
  ///
  /// In ko, this message translates to:
  /// **'끊기'**
  String get ftpDisconnect;

  /// No description provided for @ftpClosed.
  ///
  /// In ko, this message translates to:
  /// **'끊김'**
  String get ftpClosed;

  /// No description provided for @ftpUploading.
  ///
  /// In ko, this message translates to:
  /// **'올리는 중 {file}'**
  String ftpUploading(String file);

  /// No description provided for @ftpDownloading.
  ///
  /// In ko, this message translates to:
  /// **'내려받는 중 {file}'**
  String ftpDownloading(String file);

  /// No description provided for @ftpEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'연결된 클라이언트가 없어요'**
  String get ftpEmptyTitle;

  /// No description provided for @ftpEmptyHint.
  ///
  /// In ko, this message translates to:
  /// **'FTP 클라이언트가 접속하면 여기에 나타나요'**
  String get ftpEmptyHint;

  /// No description provided for @ftpSummary.
  ///
  /// In ko, this message translates to:
  /// **'연결 {open} · 누적 {total} · 받음 {received} · 보냄 {sent}'**
  String ftpSummary(int open, int total, String received, String sent);

  /// No description provided for @checkTitleBlocked.
  ///
  /// In ko, this message translates to:
  /// **'서비스를 시작할 수 없어요'**
  String get checkTitleBlocked;

  /// No description provided for @checkTitleWarning.
  ///
  /// In ko, this message translates to:
  /// **'시작하기 전에 확인하세요'**
  String get checkTitleWarning;

  /// No description provided for @checkPortInUse.
  ///
  /// In ko, this message translates to:
  /// **'{protocol} {port}를 다른 프로그램이 쓰고 있어요: {process} (PID {pid})'**
  String checkPortInUse(String protocol, int port, String process, int pid);

  /// No description provided for @checkFirewall.
  ///
  /// In ko, this message translates to:
  /// **'Windows 방화벽이 {profiles} 프로필에서 {ports} 수신을 막을 수 있어요. 이 프로그램의 허용 규칙이 없어요.'**
  String checkFirewall(String profiles, String ports);

  /// No description provided for @checkOtherDhcp.
  ///
  /// In ko, this message translates to:
  /// **'같은 망에 다른 DHCP 서버가 있어요: {servers}'**
  String checkOtherDhcp(String servers);

  /// No description provided for @checkPortsReserved.
  ///
  /// In ko, this message translates to:
  /// **'Windows가 패시브 포트 범위 {range} 중 {reserved}를 예약해 두었어요 (쓸 수 있는 포트 {free}개).'**
  String checkPortsReserved(String range, String reserved, int free);

  /// No description provided for @checkPortsReservedAdvice.
  ///
  /// In ko, this message translates to:
  /// **'다른 범위(예: 40000~40199)로 바꾸세요. 예약 범위는 netsh int ipv4 show excludedportrange protocol=tcp 로 볼 수 있어요.'**
  String get checkPortsReservedAdvice;

  /// No description provided for @checkAddRule.
  ///
  /// In ko, this message translates to:
  /// **'방화벽 규칙 추가'**
  String get checkAddRule;

  /// No description provided for @checkAddRuleHint.
  ///
  /// In ko, this message translates to:
  /// **'관리자 권한 확인 창이 떠요'**
  String get checkAddRuleHint;

  /// No description provided for @checkRuleAdded.
  ///
  /// In ko, this message translates to:
  /// **'방화벽 규칙을 추가했어요'**
  String get checkRuleAdded;

  /// No description provided for @logDropped.
  ///
  /// In ko, this message translates to:
  /// **'로그가 너무 많아 {count}건을 건너뛰었어요'**
  String logDropped(int count);

  /// No description provided for @logCheckPortInUse.
  ///
  /// In ko, this message translates to:
  /// **'{protocol} {port}를 {process} (PID {pid})가 쓰고 있어요'**
  String logCheckPortInUse(String protocol, int port, String process, int pid);

  /// No description provided for @logCheckFirewallBlocked.
  ///
  /// In ko, this message translates to:
  /// **'방화벽 허용 규칙 없음: {profiles} 프로필, {ports}'**
  String logCheckFirewallBlocked(String profiles, String ports);

  /// No description provided for @logCheckOtherDhcpServer.
  ///
  /// In ko, this message translates to:
  /// **'다른 DHCP 서버 발견: {servers}'**
  String logCheckOtherDhcpServer(String servers);

  /// No description provided for @logCheckPortsReserved.
  ///
  /// In ko, this message translates to:
  /// **'예약된 포트: {range} 중 {reserved}'**
  String logCheckPortsReserved(String range, String reserved);

  /// No description provided for @logCheckRuleAdded.
  ///
  /// In ko, this message translates to:
  /// **'방화벽 규칙을 추가했어요'**
  String get logCheckRuleAdded;

  /// No description provided for @logCheckRuleFailed.
  ///
  /// In ko, this message translates to:
  /// **'방화벽 규칙을 추가하지 못했어요 (거부되었거나 실패)'**
  String get logCheckRuleFailed;

  /// No description provided for @logTftpStarted.
  ///
  /// In ko, this message translates to:
  /// **'TFTP 서버 시작 {address}:{port} · {root}'**
  String logTftpStarted(String address, int port, String root);

  /// No description provided for @logTftpStopped.
  ///
  /// In ko, this message translates to:
  /// **'TFTP 서버를 중지했어요'**
  String get logTftpStopped;

  /// No description provided for @logTftpRrq.
  ///
  /// In ko, this message translates to:
  /// **'읽기 요청 {file} ← {client} ({mode})'**
  String logTftpRrq(String file, String client, String mode);

  /// No description provided for @logTftpWrq.
  ///
  /// In ko, this message translates to:
  /// **'쓰기 요청 {file} ← {client} ({mode})'**
  String logTftpWrq(String file, String client, String mode);

  /// No description provided for @logTftpSent.
  ///
  /// In ko, this message translates to:
  /// **'보냄 {file} → {client} · {bytes} · {seconds}초 · {rate}'**
  String logTftpSent(
    String file,
    String client,
    String bytes,
    String seconds,
    String rate,
  );

  /// No description provided for @logTftpReceived.
  ///
  /// In ko, this message translates to:
  /// **'받음 {file} ← {client} · {bytes} · {seconds}초 · {rate}'**
  String logTftpReceived(
    String file,
    String client,
    String bytes,
    String seconds,
    String rate,
  );

  /// No description provided for @logTftpFailed.
  ///
  /// In ko, this message translates to:
  /// **'실패 {file} ({client}): {reason}'**
  String logTftpFailed(String file, String client, String reason);

  /// No description provided for @logTftpBusy.
  ///
  /// In ko, this message translates to:
  /// **'{client}의 {file} 요청을 거절했어요 (동시 전송 {limit}개 초과)'**
  String logTftpBusy(String client, String file, int limit);

  /// No description provided for @logTftpMalformed.
  ///
  /// In ko, this message translates to:
  /// **'{from}에서 온 잘못된 요청'**
  String logTftpMalformed(String from);

  /// No description provided for @logTftpPortInUse.
  ///
  /// In ko, this message translates to:
  /// **'{address}:{port}를 다른 프로그램이 쓰고 있어요: {error}'**
  String logTftpPortInUse(String address, int port, String error);

  /// No description provided for @logTftpPermissionDenied.
  ///
  /// In ko, this message translates to:
  /// **'{address}:{port}를 열 권한이 없어요: {error}'**
  String logTftpPermissionDenied(String address, int port, String error);

  /// No description provided for @logTftpBindFailed.
  ///
  /// In ko, this message translates to:
  /// **'{address}:{port}를 열지 못했어요: {error}'**
  String logTftpBindFailed(String address, int port, String error);

  /// No description provided for @logTftpPacketIn.
  ///
  /// In ko, this message translates to:
  /// **'요청 패킷 ← {client}'**
  String logTftpPacketIn(String client);

  /// No description provided for @logFtpStarted.
  ///
  /// In ko, this message translates to:
  /// **'FTP 서버 시작 {address}:{port} · {root} · 패시브 {passive}'**
  String logFtpStarted(String address, int port, String root, String passive);

  /// No description provided for @logFtpStopped.
  ///
  /// In ko, this message translates to:
  /// **'FTP 서버를 중지했어요'**
  String get logFtpStopped;

  /// No description provided for @logFtpConnected.
  ///
  /// In ko, this message translates to:
  /// **'접속 {client}'**
  String logFtpConnected(String client);

  /// No description provided for @logFtpDisconnected.
  ///
  /// In ko, this message translates to:
  /// **'끊김 {client} {user} ({seconds}초)'**
  String logFtpDisconnected(String client, String user, int seconds);

  /// No description provided for @logFtpLogin.
  ///
  /// In ko, this message translates to:
  /// **'로그인 {user} ({client})'**
  String logFtpLogin(String user, String client);

  /// No description provided for @logFtpLoginFailed.
  ///
  /// In ko, this message translates to:
  /// **'로그인 실패 {user} ({client})'**
  String logFtpLoginFailed(String user, String client);

  /// No description provided for @logFtpDownload.
  ///
  /// In ko, this message translates to:
  /// **'내려받음 {file} → {user} · {bytes} · {seconds}초 · {rate}'**
  String logFtpDownload(
    String file,
    String user,
    String bytes,
    String seconds,
    String rate,
  );

  /// No description provided for @logFtpUpload.
  ///
  /// In ko, this message translates to:
  /// **'올림 {file} ← {user} · {bytes} · {seconds}초 · {rate}'**
  String logFtpUpload(
    String file,
    String user,
    String bytes,
    String seconds,
    String rate,
  );

  /// No description provided for @logFtpTransferFailed.
  ///
  /// In ko, this message translates to:
  /// **'전송 실패 {file} ({user}): {error}'**
  String logFtpTransferFailed(String file, String user, String error);

  /// No description provided for @logFtpDenied.
  ///
  /// In ko, this message translates to:
  /// **'거부 {command} {path} ({user}, {client})'**
  String logFtpDenied(String command, String path, String user, String client);

  /// No description provided for @logFtpDeleted.
  ///
  /// In ko, this message translates to:
  /// **'삭제 {path} ({user})'**
  String logFtpDeleted(String path, String user);

  /// No description provided for @logFtpMkdir.
  ///
  /// In ko, this message translates to:
  /// **'폴더 만듦 {path} ({user})'**
  String logFtpMkdir(String path, String user);

  /// No description provided for @logFtpRmdir.
  ///
  /// In ko, this message translates to:
  /// **'폴더 지움 {path} ({user})'**
  String logFtpRmdir(String path, String user);

  /// No description provided for @logFtpRenamed.
  ///
  /// In ko, this message translates to:
  /// **'이름 바꿈 {from} → {to} ({user})'**
  String logFtpRenamed(String from, String to, String user);

  /// No description provided for @logFtpTooMany.
  ///
  /// In ko, this message translates to:
  /// **'{client} 연결 거절 (동시 접속 {limit}개 초과)'**
  String logFtpTooMany(String client, int limit);

  /// No description provided for @logFtpIdleTimeout.
  ///
  /// In ko, this message translates to:
  /// **'유휴 시간 초과로 끊음 {client} {user}'**
  String logFtpIdleTimeout(String client, String user);

  /// No description provided for @logFtpKicked.
  ///
  /// In ko, this message translates to:
  /// **'관리자가 끊음 {client} {user}'**
  String logFtpKicked(String client, String user);

  /// No description provided for @logFtpNoPassivePort.
  ///
  /// In ko, this message translates to:
  /// **'패시브 포트 {range}에 빈 포트가 없어요'**
  String logFtpNoPassivePort(String range);

  /// No description provided for @logFtpPortInUse.
  ///
  /// In ko, this message translates to:
  /// **'{address}:{port}를 다른 프로그램이 쓰고 있어요: {error}'**
  String logFtpPortInUse(String address, int port, String error);

  /// No description provided for @logFtpPermissionDenied.
  ///
  /// In ko, this message translates to:
  /// **'{address}:{port}를 열 권한이 없어요: {error}'**
  String logFtpPermissionDenied(String address, int port, String error);

  /// No description provided for @logFtpBindFailed.
  ///
  /// In ko, this message translates to:
  /// **'{address}:{port}를 열지 못했어요: {error}'**
  String logFtpBindFailed(String address, int port, String error);

  /// No description provided for @logFtpCommand.
  ///
  /// In ko, this message translates to:
  /// **'{client} › {command}'**
  String logFtpCommand(String client, String command);

  /// 업데이트 알림의 변경 항목 아래. 개수 제한으로 뺀 항목이 있을 때.
  ///
  /// In ko, this message translates to:
  /// **'외 {count}건'**
  String updateMoreChanges(int count);

  /// No description provided for @updateViewReleaseNotes.
  ///
  /// In ko, this message translates to:
  /// **'릴리스 노트 보기'**
  String get updateViewReleaseNotes;

  /// No description provided for @logLevelTooltip.
  ///
  /// In ko, this message translates to:
  /// **'표시할 최소 수준'**
  String get logLevelTooltip;

  /// No description provided for @firewallHelpButton.
  ///
  /// In ko, this message translates to:
  /// **'해결 방법'**
  String get firewallHelpButton;

  /// No description provided for @firewallHintChip.
  ///
  /// In ko, this message translates to:
  /// **'방화벽 안내'**
  String get firewallHintChip;

  /// No description provided for @firewallHelpTitle.
  ///
  /// In ko, this message translates to:
  /// **'방화벽에서 허용하는 방법'**
  String get firewallHelpTitle;

  /// No description provided for @firewallHelpWhy.
  ///
  /// In ko, this message translates to:
  /// **'이 프로그램이 {ports}로 들어오는 연결을 받으려면 Windows 방화벽의 허용이 필요해요. 지금은 {profiles} 프로필에 허용 규칙이 없어요.'**
  String firewallHelpWhy(String ports, String profiles);

  /// No description provided for @firewallHelpProgram.
  ///
  /// In ko, this message translates to:
  /// **'프로그램'**
  String get firewallHelpProgram;

  /// No description provided for @firewallHelpAutoTitle.
  ///
  /// In ko, this message translates to:
  /// **'1. 자동으로 추가 (권장)'**
  String get firewallHelpAutoTitle;

  /// No description provided for @firewallHelpAutoBody.
  ///
  /// In ko, this message translates to:
  /// **'단추를 누르면 Windows가 관리자 확인 창을 띄워요. 확인하면 이 프로그램을 모든 네트워크 프로필에서 허용하는 규칙이 추가돼요.'**
  String get firewallHelpAutoBody;

  /// No description provided for @firewallHelpManualTitle.
  ///
  /// In ko, this message translates to:
  /// **'2. 직접 허용 ({os})'**
  String firewallHelpManualTitle(String os);

  /// No description provided for @firewallStepsWin11.
  ///
  /// In ko, this message translates to:
  /// **'시작 → 설정 → 개인 정보 및 보안 → Windows 보안 → 방화벽 및 네트워크 보호\n[방화벽에서 앱 허용] → [설정 변경] → [다른 앱 허용…]\n[찾아보기…]로 위의 프로그램을 고르고 [추가]\n목록의 Lab Daemon에서 [개인]과 [공용]을 모두 체크하고 [확인]'**
  String get firewallStepsWin11;

  /// No description provided for @firewallStepsWin10.
  ///
  /// In ko, this message translates to:
  /// **'시작 → 설정 → 업데이트 및 보안 → Windows 보안 → 방화벽 및 네트워크 보호\n[방화벽을 통해 앱 허용] → [설정 변경] → [다른 앱 허용…]\n[찾아보기…]로 위의 프로그램을 고르고 [추가]\n목록의 Lab Daemon에서 [개인]과 [공용]을 모두 체크하고 [확인]'**
  String get firewallStepsWin10;

  /// No description provided for @firewallOpenAllowedApps.
  ///
  /// In ko, this message translates to:
  /// **'허용된 앱 창 열기'**
  String get firewallOpenAllowedApps;

  /// No description provided for @firewallHelpCommandTitle.
  ///
  /// In ko, this message translates to:
  /// **'3. 명령으로 추가 (관리자 권한 PowerShell 또는 명령 프롬프트)'**
  String get firewallHelpCommandTitle;

  /// No description provided for @firewallHelpInstallerNote.
  ///
  /// In ko, this message translates to:
  /// **'설치 프로그램으로 설치한 Lab Daemon은 설치할 때 이 규칙이 자동으로 들어가요. 다른 위치에서 실행한 프로그램(개발 빌드 등)은 경로가 달라서 따로 허용해야 해요.'**
  String get firewallHelpInstallerNote;

  /// No description provided for @firewallHelpPolicyNote.
  ///
  /// In ko, this message translates to:
  /// **'회사 PC는 관리자 정책으로 규칙 추가가 막혀 있을 수 있어요. 그때는 IT 담당자에게 위 프로그램과 포트의 허용을 요청하세요.'**
  String get firewallHelpPolicyNote;

  /// No description provided for @commandCopied.
  ///
  /// In ko, this message translates to:
  /// **'명령을 복사했어요'**
  String get commandCopied;

  /// No description provided for @logCheckFirewallHint.
  ///
  /// In ko, this message translates to:
  /// **'해결 방법은 서비스 화면 위쪽의 [방화벽 안내]에서 볼 수 있어요'**
  String get logCheckFirewallHint;

  /// No description provided for @openRootFolder.
  ///
  /// In ko, this message translates to:
  /// **'탐색기로 루트 폴더 열기'**
  String get openRootFolder;

  /// No description provided for @logCapacityTooltip.
  ///
  /// In ko, this message translates to:
  /// **'보관할 로그 줄 수'**
  String get logCapacityTooltip;

  /// No description provided for @logCapacityLines.
  ///
  /// In ko, this message translates to:
  /// **'{count}줄'**
  String logCapacityLines(int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
