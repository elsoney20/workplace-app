import 'package:material_ui/material_ui.dart';

import '../config/brand_config.dart';

/// Shows the brand logo, or a letter avatar if no logo is configured yet.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    final logo = BrandConfig.logoAsset;
    if (logo != null) {
      return Image.asset(logo, width: size, height: size);
    }

    final name = BrandConfig.localizedAppName(Localizations.localeOf(context));
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: BrandConfig.primaryColor,
      child: Text(
        name.characters.first.toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.5,
        ),
      ),
    );
  }
}
