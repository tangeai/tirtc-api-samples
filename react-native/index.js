import {AppRegistry, LogBox} from 'react-native';
import {SafeAreaProvider} from 'react-native-safe-area-context';
import App from './src/App';

if (__DEV__) {
  LogBox.ignoreAllLogs(true);
}

function Root() {
  return (
    <SafeAreaProvider>
      <App />
    </SafeAreaProvider>
  );
}

AppRegistry.registerComponent('TiRtcExample', () => Root);
