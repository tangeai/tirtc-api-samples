import {StyleSheet} from 'react-native';
import {exampleTheme} from './ExampleUi';

export const commandPanelStyles = StyleSheet.create({
  root: {
    flex: 1,
    justifyContent: 'flex-end',
  },
  backdrop: {
    position: 'absolute',
    top: 0,
    right: 0,
    bottom: 0,
    left: 0,
    backgroundColor: 'transparent',
  },
  sheet: {
    height: '50%',
    borderTopLeftRadius: 16,
    borderTopRightRadius: 16,
    backgroundColor: exampleTheme.background,
    overflow: 'hidden',
  },
  header: {
    minHeight: 56,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 10,
  },
  title: {
    flex: 1,
    color: exampleTheme.textPrimary,
    fontSize: 16,
    fontWeight: '600',
  },
  closeButton: {
    width: 40,
    height: 40,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
  },
  closeText: {
    color: exampleTheme.textHint,
    fontSize: 28,
    lineHeight: 30,
  },
  divider: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: exampleTheme.inputBorder,
  },
  body: {
    padding: 14,
    gap: 10,
  },
  connectionPill: {
    alignSelf: 'flex-start',
    borderRadius: 999,
    borderWidth: 1,
    borderColor: 'rgba(132,130,130,0.32)',
    backgroundColor: 'rgba(132,130,130,0.10)',
    paddingHorizontal: 8,
    paddingVertical: 4,
  },
  connectionPillReady: {
    borderColor: 'rgba(101,146,135,0.32)',
    backgroundColor: 'rgba(101,146,135,0.10)',
  },
  connectionText: {
    color: exampleTheme.textSecondary,
    fontSize: 11,
    fontWeight: '600',
  },
  connectionTextReady: {
    color: exampleTheme.primary,
  },
  commandRow: {
    flexDirection: 'row',
    alignItems: 'stretch',
    gap: 8,
  },
  commandIdWrap: {
    flex: 1,
  },
  inputLabel: {
    color: exampleTheme.textSecondary,
    fontSize: 12,
    fontWeight: '600',
    marginBottom: 4,
  },
  input: {
    minHeight: 44,
    borderWidth: 1,
    borderColor: exampleTheme.inputBorder,
    borderRadius: 4,
    backgroundColor: exampleTheme.surface,
    color: exampleTheme.textPrimary,
    fontSize: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  segmented: {
    alignSelf: 'flex-end',
    minHeight: 44,
    flexDirection: 'row',
    borderWidth: 1,
    borderColor: exampleTheme.inputBorder,
    borderRadius: 20,
    overflow: 'hidden',
    backgroundColor: exampleTheme.surface,
  },
  modeButton: {
    minWidth: 58,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 10,
  },
  modeButtonSelected: {
    backgroundColor: 'rgba(101,146,135,0.18)',
  },
  modeText: {
    color: exampleTheme.textSecondary,
    fontSize: 12,
    fontWeight: '600',
  },
  modeTextSelected: {
    color: exampleTheme.primary,
  },
  payloadWrap: {
    gap: 0,
  },
  payloadInput: {
    minHeight: 62,
    textAlignVertical: 'top',
  },
  errorText: {
    color: exampleTheme.failure,
    fontSize: 12,
  },
  presets: {
    gap: 8,
  },
  presetsTitle: {
    color: exampleTheme.textSecondary,
    fontSize: 12,
    fontWeight: '600',
  },
  presetRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  presetChip: {
    minHeight: 32,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: exampleTheme.inputBorder,
    backgroundColor: exampleTheme.surface,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 12,
  },
  disabledChip: {
    opacity: 0.5,
  },
  presetText: {
    color: exampleTheme.textPrimary,
    fontSize: 12,
    fontWeight: '500',
  },
  sendRow: {
    alignItems: 'flex-end',
  },
  sendButton: {
    minWidth: 96,
    minHeight: 40,
    borderRadius: 20,
    backgroundColor: exampleTheme.primary,
    flexDirection: 'row',
    gap: 8,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  disabledSendButton: {
    backgroundColor: exampleTheme.textHint,
  },
  sendText: {
    color: exampleTheme.foreground,
    fontSize: 13,
    fontWeight: '600',
  },
  events: {
    gap: 6,
    paddingBottom: 8,
  },
  emptyEvents: {
    color: exampleTheme.textSecondary,
    fontSize: 12,
    paddingVertical: 10,
  },
  eventRow: {
    borderRadius: 10,
    padding: 8,
  },
  eventTitleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  eventDirection: {
    fontSize: 14,
    fontWeight: '700',
  },
  eventTitle: {
    flex: 1,
    fontSize: 12,
    fontWeight: '700',
  },
  eventCode: {
    color: exampleTheme.textSecondary,
    fontSize: 11,
  },
  eventPayload: {
    color: exampleTheme.textSecondary,
    fontSize: 11,
    marginTop: 4,
  },
});
