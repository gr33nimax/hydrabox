import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/app/app_settings_controller.dart';
import 'package:meow_client/data/local/app_settings_store.dart';

void main() {
  test('performance preset updates URLTest and lookup defaults', () {
    final controller = AppSettingsController();

    final change = controller.setPerformanceMode(AppPerformanceMode.economy);

    expect(change.changed, isTrue);
    expect(change.configReason, 'performance mode changed');
    expect(change.syncRuntimePerformanceFlags, isTrue);
    expect(controller.urlTestConcurrency, appSettingsEconomyUrlTestConcurrency);
    expect(
      controller.locationLookupLimit,
      appSettingsEconomyLocationLookupLimit,
    );
  });

  test('DNS preset updates resolver together with preset', () {
    final controller = AppSettingsController();

    final change = controller.setDnsDirectPreset('cloudflare_doh');

    expect(change.changed, isTrue);
    expect(change.configReason, 'dns direct preset changed');
    expect(controller.dnsDirectPreset, 'cloudflare_doh');
    expect(
      controller.dnsDirectResolver,
      'https://dns.cloudflare.com/dns-query',
    );
  });

  test('toState keeps external runtime selection fields supplied by app', () {
    final controller = AppSettingsController()
      ..setLocale('ru')
      ..setTlsFragmentationMode(TlsFragmentationMode.record);

    final state = controller.toState(
      onboardingCompleted: true,
      acceptedLegalVersion: '0.2.0',
      acceptedLegalAtMillis: 42,
      activeProfileId: 'sub-1',
      selectedProxyTag: 'vless-1',
    );

    expect(state.onboardingCompleted, isTrue);
    expect(state.acceptedLegalVersion, '0.2.0');
    expect(state.acceptedLegalAtMillis, 42);
    expect(state.activeProfileId, 'sub-1');
    expect(state.selectedProxyTag, 'vless-1');
    expect(state.localeCode, 'ru');
    expect(state.tlsFragmentationMode, TlsFragmentationMode.record);
  });
}
