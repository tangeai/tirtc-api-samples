"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const electron_1 = require("electron");
const application_1 = require("./application");
void (0, application_1.startExampleApplication)().catch((error) => {
    console.error('Electron Example failed to start', error);
    electron_1.app.quit();
});
