import 'models.dart';

bool get canInstallUpdates => false;

ReleaseFile? fileFor(Release release) => null;

Future<void> installUpdate(String url, ReleaseFile file, void Function(double) onProgress) async {}
