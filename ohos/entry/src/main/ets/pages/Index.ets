import { ExampleApp } from '../example/ExampleApp';

@Entry
@Component
struct Index {
  build() {
    Stack() {
      ExampleApp()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFF8E8')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
