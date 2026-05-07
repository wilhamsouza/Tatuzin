import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

abstract interface class CheckoutLauncher {
  Future<bool> openExternal(String url);

  Future<void> copyLink(String url);
}

class UrlLauncherCheckoutLauncher implements CheckoutLauncher {
  const UrlLauncherCheckoutLauncher();

  @override
  Future<bool> openExternal(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      return false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Future<void> copyLink(String url) {
    return Clipboard.setData(ClipboardData(text: url));
  }
}
