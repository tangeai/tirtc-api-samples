import {app} from 'electron';

import {startExampleApplication} from './application';

void startExampleApplication().catch((error) => {
  console.error('Electron Example failed to start', error);
  app.quit();
});
