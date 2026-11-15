import 'models.dart';

bool get canInstallUpdates => false;

UpdatePackage? packageFor(ReleaseInfo release) => null;

Future<void> installUpdate(String url, UpdatePackage package, void Function(double) onProgress) async {}
