import React, {useEffect, useRef} from 'react';
import {Animated, StyleSheet, Text, View} from 'react-native';
import {automationTestId, exampleTheme} from './ExampleUi';

export function StreamMessageBubble({text}: {text: string | null}) {
  const translateX = useRef(new Animated.Value(32)).current;
  const displayText = text?.trim() ? text.trim() : '-';

  useEffect(() => {
    if (text === null) {
      return;
    }
    translateX.setValue(32);
    Animated.timing(translateX, {
      toValue: 0,
      duration: 260,
      useNativeDriver: true,
    }).start();
  }, [text, translateX]);

  if (text === null) {
    return null;
  }

  return (
    <Animated.View
      accessible
      accessibilityLabel="TiRTC Stream Message Bubble"
      testID={automationTestId('TiRTC Stream Message Bubble')}
      style={[styles.root, {transform: [{translateX}]}]}>
      <View style={styles.bubble}>
        <Text style={styles.text}>流消息：{displayText}</Text>
        <View style={styles.tail} />
      </View>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  root: {
    maxWidth: '100%',
    alignSelf: 'flex-end',
  },
  bubble: {
    minWidth: 172,
    maxWidth: '100%',
    minHeight: 38,
    borderRadius: 25,
    backgroundColor: 'rgba(255,255,255,0.87)',
    paddingLeft: 16,
    paddingRight: 26,
    paddingVertical: 9,
    elevation: 6,
  },
  tail: {
    position: 'absolute',
    right: 3,
    bottom: 7,
    width: 14,
    height: 14,
    borderRadius: 3,
    backgroundColor: 'rgba(255,255,255,0.87)',
    transform: [{rotate: '45deg'}],
  },
  text: {
    color: '#6B7280',
    flexShrink: 1,
    fontSize: 13,
    fontStyle: 'italic',
    fontWeight: '400',
    lineHeight: 18,
  },
});
