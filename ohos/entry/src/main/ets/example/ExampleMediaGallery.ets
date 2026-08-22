import type { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';

export async function saveMediaFileToGallery(
  context: common.UIAbilityContext,
  sourcePath: string,
  mediaKind: string,
): Promise<boolean> {
  if (!sourcePath.startsWith('/') || (mediaKind !== 'snapshot' && mediaKind !== 'recording')) {
    return false;
  }
  const extension = mediaKind === 'snapshot' ? 'jpg' : 'mp4';
  const photoType = mediaKind === 'snapshot' ? photoAccessHelper.PhotoType.IMAGE : photoAccessHelper.PhotoType.VIDEO;
  const creationConfig: photoAccessHelper.PhotoCreationConfig = {
    title: `TiStore-${Date.now()}`,
    fileNameExtension: extension,
    photoType,
    subtype: photoAccessHelper.PhotoSubtype.DEFAULT,
  };
  let sourceFile: fileIo.File | undefined;
  let destinationFile: fileIo.File | undefined;
  try {
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    const destinations = await helper.showAssetsCreationDialog([sourcePath], [creationConfig]);
    if (destinations.length !== 1) {
      return false;
    }
    sourceFile = await fileIo.open(sourcePath, fileIo.OpenMode.READ_ONLY);
    destinationFile = await fileIo.open(destinations[0], fileIo.OpenMode.WRITE_ONLY);
    await fileIo.copyFile(sourceFile.fd, destinationFile.fd);
    return true;
  } catch (_) {
    return false;
  } finally {
    if (sourceFile !== undefined) {
      fileIo.closeSync(sourceFile);
    }
    if (destinationFile !== undefined) {
      fileIo.closeSync(destinationFile);
    }
  }
}
