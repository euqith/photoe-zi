class LutPreset {
  final String id;
  final String name;
  final String category;
  final String? assetPath;
  final String? customFilePath;
  final bool isCustom;

  const LutPreset({
    required this.id,
    required this.name,
    required this.category,
    this.assetPath,
    this.customFilePath,
    this.isCustom = false,
  });

  static const List<LutPreset> builtInPresets = [
    LutPreset(
      id: 'none',
      name: 'Original (No LUT)',
      category: 'Standard',
    ),
    LutPreset(
      id: 'classic_chrome',
      name: 'Classic Chrome',
      category: 'Fujifilm Sim',
      assetPath: 'assets/luts/classic_chrome.cube',
    ),
    LutPreset(
      id: 'classic_neg',
      name: 'Classic Neg',
      category: 'Fujifilm Sim',
      assetPath: 'assets/luts/classic_neg.cube',
    ),
    LutPreset(
      id: 'kodachrome',
      name: 'Kodachrome 64',
      category: 'Vintage Film',
      assetPath: 'assets/luts/kodachrome.cube',
    ),
    LutPreset(
      id: 'japanese_airy',
      name: 'Japanese Airy',
      category: 'Portrait',
      assetPath: 'assets/luts/japanese_airy.cube',
    ),
    LutPreset(
      id: 'bw_acros',
      name: 'B&W Acros',
      category: 'Monochrome',
      assetPath: 'assets/luts/bw_acros.cube',
    ),
  ];
}
