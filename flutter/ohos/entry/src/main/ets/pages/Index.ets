import common from '@ohos.app.ability.common';
import { FlutterPage } from '@ohos/flutter_ohos';

let storage = LocalStorage.getShared();
const kEventBackPress = 'EVENT_BACK_PRESS';

@Entry(storage)
@Component
struct Index {
  private context = getContext(this) as common.UIAbilityContext;
  @LocalStorageLink('viewId') viewId: string = '';

  build() {
    Column() {
      FlutterPage({ viewId: this.viewId })
    }
  }

  onBackPress(): boolean {
    this.context.eventHub.emit(kEventBackPress);
    return true;
  }
}
