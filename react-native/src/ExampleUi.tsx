import React, {ReactNode} from 'react';
import {
  ActivityIndicator,
  KeyboardTypeOptions,
  Platform,
  Pressable,
  StyleProp,
  StatusBar,
  Text,
  TextInput,
  TextInputProps,
  View,
  ViewStyle,
} from 'react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {exampleTheme, uiStyles} from './ExampleUiStyles';

export {exampleTheme, uiStyles};

const IOS_SAFE_AREA_TOP_FALLBACK = 54;
const IOS_STAGE_TOP_GAP = 12;

export function ExampleScreenRoot({
  children,
  style,
}: {
  children: ReactNode;
  style?: StyleProp<ViewStyle>;
}) {
  const insets = useSafeAreaInsets();
  const topInset = topSafeAreaInset(insets.top);
  return (
    <View style={[uiStyles.configureRoot, {paddingTop: topInset}, style]}>
      <StatusBar barStyle="dark-content" backgroundColor={exampleTheme.background} />
      {children}
    </View>
  );
}

export function ConfigureShell({children}: {children: ReactNode}) {
  return <View style={uiStyles.configureBody}>{children}</View>;
}

export function ConfigureHeader({
  title = 'Ti RTC',
  subtitle = 'Based on React Native',
  actionLabel,
  onAction,
}: {
  title?: string;
  subtitle?: string;
  actionLabel?: string;
  onAction?: () => void;
}) {
  return (
    <View style={uiStyles.header}>
      <View style={uiStyles.brandWrap}>
        <Text style={uiStyles.brand}>{title}</Text>
        {subtitle ? <Text style={uiStyles.brandSubtitle}>{subtitle}</Text> : null}
      </View>
      {actionLabel ? (
        <Pressable
          accessible
          accessibilityRole="button"
          accessibilityLabel={`TiRTC ${actionLabel}`}
          testID={automationTestId(`TiRTC ${actionLabel}`)}
          style={uiStyles.headerAction}
          onPress={onAction}>
          <Text style={uiStyles.headerActionText}>{actionLabel}</Text>
        </Pressable>
      ) : null}
    </View>
  );
}

export function BackHeader({
  title,
  onBack,
  accessibilityLabel,
}: {
  title: string;
  onBack: () => void;
  accessibilityLabel: string;
}) {
  return (
    <View style={uiStyles.header}>
      <Pressable
        accessible
        accessibilityRole="button"
        accessibilityLabel={accessibilityLabel}
        testID={automationTestId(accessibilityLabel)}
        onPress={onBack}
        style={uiStyles.backButton}>
        <Text style={uiStyles.backButtonText}>‹</Text>
      </Pressable>
      <Text style={uiStyles.headerTitle}>{title}</Text>
    </View>
  );
}

export function InputField({
  label,
  hint,
  value,
  onChangeText,
  accessibilityLabel,
  autoCapitalize,
  autoCorrect,
  multiline,
  keyboardType,
  style,
}: {
  label: string;
  hint: string;
  value: string;
  onChangeText: (value: string) => void;
  accessibilityLabel: string;
  autoCapitalize?: TextInputProps['autoCapitalize'];
  autoCorrect?: TextInputProps['autoCorrect'];
  multiline?: boolean;
  keyboardType?: KeyboardTypeOptions;
  style?: StyleProp<ViewStyle>;
}) {
  return (
    <View style={[uiStyles.inputWrap, style]}>
      <Text style={uiStyles.inputLabel}>{label}</Text>
      <TextInput
        accessibilityLabel={accessibilityLabel}
        testID={automationTestId(accessibilityLabel)}
        value={value}
        onChangeText={onChangeText}
        placeholder={hint}
        placeholderTextColor={exampleTheme.textSecondary}
        autoCapitalize={autoCapitalize}
        autoCorrect={autoCorrect}
        multiline={multiline}
        keyboardType={keyboardType}
        style={[uiStyles.input, multiline ? uiStyles.multilineInput : null]}
      />
    </View>
  );
}

export function FieldRow({children}: {children: ReactNode}) {
  return <View style={uiStyles.fieldRow}>{children}</View>;
}

export function ChoicePill({
  label,
  selected,
  onPress,
  accessibilityLabel,
}: {
  label: string;
  selected: boolean;
  onPress: () => void;
  accessibilityLabel: string;
}) {
  return (
    <Pressable
      accessible
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      testID={automationTestId(accessibilityLabel)}
      onPress={onPress}
      style={[uiStyles.choice, selected ? uiStyles.choiceSelected : null]}>
      <Text style={[uiStyles.choiceText, selected ? uiStyles.choiceTextSelected : null]}>
        {label}
      </Text>
    </Pressable>
  );
}

export function PrimaryButton({
  label,
  onPress,
  accessibilityLabel,
  disabled,
  busy,
  danger,
}: {
  label: string;
  onPress: () => void;
  accessibilityLabel: string;
  disabled?: boolean;
  busy?: boolean;
  danger?: boolean;
}) {
  return (
    <Pressable
      accessible
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      testID={automationTestId(accessibilityLabel)}
      importantForAccessibility="yes"
      collapsable={false}
      disabled={disabled || busy}
      onPress={onPress}
      style={[
        uiStyles.primaryButton,
        danger ? uiStyles.dangerButton : null,
        disabled || busy ? uiStyles.disabledButton : null,
      ]}>
      {busy ? <ActivityIndicator color={exampleTheme.foreground} size="small" /> : null}
      <Text style={uiStyles.primaryButtonText}>{label}</Text>
    </Pressable>
  );
}

export function OutlineButton({
  label,
  onPress,
  accessibilityLabel,
  disabled,
  busy,
  compact,
}: {
  label: string;
  onPress: () => void;
  accessibilityLabel: string;
  disabled?: boolean;
  busy?: boolean;
  compact?: boolean;
}) {
  return (
    <Pressable
      accessible
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      testID={automationTestId(accessibilityLabel)}
      importantForAccessibility="yes"
      collapsable={false}
      disabled={disabled || busy}
      onPress={onPress}
      style={[
        uiStyles.outlineButton,
        compact ? uiStyles.compactOutlineButton : null,
        disabled || busy ? uiStyles.disabledOutlineButton : null,
      ]}>
      {busy ? <ActivityIndicator color={exampleTheme.primary} size="small" /> : null}
      <Text style={[uiStyles.outlineButtonText, disabled ? uiStyles.disabledText : null]}>
        {label}
      </Text>
    </Pressable>
  );
}

export function StageControlButton({
  label,
  onPress,
  accessibilityLabel,
  tone = 'primary',
  disabled,
  busy,
}: {
  label: string;
  onPress: () => void;
  accessibilityLabel: string;
  tone?: 'primary' | 'danger' | 'surface' | 'warning';
  disabled?: boolean;
  busy?: boolean;
}) {
  const surface = tone === 'surface';
  return (
    <Pressable
      accessible
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      testID={automationTestId(accessibilityLabel)}
      importantForAccessibility="yes"
      collapsable={false}
      disabled={disabled || busy}
      onPress={onPress}
      style={[
        uiStyles.stageControlButton,
        tone === 'danger' ? uiStyles.stageControlDanger : null,
        surface ? uiStyles.stageControlSurface : null,
        tone === 'warning' ? uiStyles.stageControlWarning : null,
        disabled || busy ? uiStyles.stageControlDisabled : null,
      ]}>
      {busy ? (
        <ActivityIndicator color={surface ? exampleTheme.primary : exampleTheme.foreground} size="small" />
      ) : null}
      <Text style={[uiStyles.stageControlText, surface ? uiStyles.stageControlSurfaceText : null]}>
        {label}
      </Text>
    </Pressable>
  );
}

export function TextLink({
  label,
  onPress,
  accessibilityLabel,
}: {
  label: string;
  onPress: () => void;
  accessibilityLabel: string;
}) {
  return (
    <Pressable
      accessible
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      testID={automationTestId(accessibilityLabel)}
      onPress={onPress}
      style={uiStyles.textLink}>
      <Text style={uiStyles.textLinkText}>{label}</Text>
    </Pressable>
  );
}

export function StatusText({children}: {children: ReactNode}) {
  return <Text style={uiStyles.statusText}>{children}</Text>;
}

export function DiagnosticsPanel({
  title,
  lines,
  accessibilityLabel,
}: {
  title: string;
  lines: readonly string[];
  accessibilityLabel: string;
}) {
  return (
    <View
      accessibilityLabel={accessibilityLabel}
      testID={automationTestId(accessibilityLabel)}
      style={uiStyles.diagnosticsPanel}>
      <Text style={uiStyles.diagnosticsTitle}>{title}</Text>
      {lines.map((line) => (
        <Text key={line} style={uiStyles.diagnosticsLine}>
          {line}
        </Text>
      ))}
    </View>
  );
}

export function VideoStage({
  children,
  label,
  failed,
  showOverlay = true,
}: {
  children?: ReactNode;
  label: string;
  failed?: boolean;
  showOverlay?: boolean;
}) {
  return (
    <View
      accessible
      accessibilityLabel={label}
      testID={automationTestId(`TiRTC Stage ${label}`)}
      style={uiStyles.videoStage}>
      <View style={uiStyles.videoContent}>{children}</View>
      {showOverlay ? (
        <View style={uiStyles.stageOverlay}>
          <View style={uiStyles.stageBadge}>
            {failed ? null : <ActivityIndicator color={exampleTheme.foreground} size="small" />}
            <Text style={uiStyles.stageLabel}>{label}</Text>
          </View>
        </View>
      ) : null}
    </View>
  );
}

export function TopBar({
  title,
  onBack,
  children,
}: {
  title: string;
  onBack: () => void;
  children?: ReactNode;
}) {
  const insets = useSafeAreaInsets();
  const topInset = topSafeAreaInset(insets.top);
  const topGap = stageTopGap();
  return (
    <View
      style={[uiStyles.topBar, {minHeight: topInset + topGap + 56, paddingTop: topInset + topGap}]}
      accessible={false}
      importantForAccessibility="no"
      collapsable={false}>
      <StatusBar barStyle="dark-content" backgroundColor={exampleTheme.background} />
      <Pressable
        accessible
        accessibilityRole="button"
        accessibilityLabel="TiRTC Back"
        testID={automationTestId('TiRTC Back')}
        importantForAccessibility="yes"
        collapsable={false}
        onPress={onBack}
        style={uiStyles.topBackButton}>
        <Text style={uiStyles.topBackText}>‹</Text>
      </Pressable>
      <View style={[uiStyles.topTitleWrap, uiStyles.noPointerEvents]}>
        <Text style={uiStyles.topTitle} numberOfLines={1} ellipsizeMode="tail">
          {title}
        </Text>
      </View>
      <View
        style={uiStyles.topActions}
        accessible={false}
        importantForAccessibility="no"
        collapsable={false}>
        {children}
      </View>
    </View>
  );
}

function androidStatusBarInset(): number {
  return Platform.OS === 'android' ? StatusBar.currentHeight ?? 0 : 0;
}

function topSafeAreaInset(iosTopInset: number): number {
  if (Platform.OS === 'ios') {
    return iosTopInset > 0 ? iosTopInset : IOS_SAFE_AREA_TOP_FALLBACK;
  }
  return androidStatusBarInset();
}

function stageTopGap(): number {
  return Platform.OS === 'ios' ? IOS_STAGE_TOP_GAP : 0;
}

export function automationTestId(label: string): string {
  return label.replace(/[^A-Za-z0-9_]+/g, '_').replace(/^_+|_+$/g, '');
}
