/*
 * Deskflow -- mouse and keyboard sharing utility
 * SPDX-FileCopyrightText: (C) 2026 Deskflow Developers
 * SPDX-License-Identifier: GPL-2.0-only WITH LicenseRef-OpenSSL-Exception
 */

#include "OSXComputerTests.h"

#include "platform/OSXComputer.h"

constexpr auto kGestureType = static_cast<CGEventType>(29);

void OSXComputerTests::navigationGesturesEnabledFromOptions_enabledOption_returnsTrue()
{
  const OptionsList enabled = {kOptionMacNavigationGestures, 1};

  QVERIFY(OSXComputer::navigationGesturesEnabledFromOptions(enabled, false));
}

void OSXComputerTests::navigationGesturesEnabledFromOptions_disabledOption_returnsFalse()
{
  const OptionsList disabled = {kOptionMacNavigationGestures, 0};

  QVERIFY(!OSXComputer::navigationGesturesEnabledFromOptions(disabled, true));
}

void OSXComputerTests::navigationGesturesEnabledFromOptions_unrelatedOption_preservesCurrentValue()
{
  const OptionsList unrelated = {kOptionClipboardSharing, 1};

  QVERIFY(OSXComputer::navigationGesturesEnabledFromOptions(unrelated, true));
}

void OSXComputerTests::navigationGesturesEnabledFromOptions_malformedOptions_preservesCurrentValue()
{
  const OptionsList malformed = {kOptionMacNavigationGestures};

  QVERIFY(OSXComputer::navigationGesturesEnabledFromOptions(malformed, true));
}

void OSXComputerTests::classifyNavigationGestureButton_swipeLeft_returnsExtra0()
{
  QCOMPARE(OSXComputer::classifyNavigationGestureButton(kGestureType, false, true, 1.0), kButtonExtra0);
}

void OSXComputerTests::classifyNavigationGestureButton_swipeRight_returnsExtra1()
{
  QCOMPARE(OSXComputer::classifyNavigationGestureButton(kGestureType, false, true, -1.0), kButtonExtra1);
}

void OSXComputerTests::classifyNavigationGestureButton_disabled_returnsNone()
{
  QCOMPARE(OSXComputer::classifyNavigationGestureButton(kGestureType, false, false, 1.0), kButtonNone);
}

void OSXComputerTests::classifyNavigationGestureButton_localScreen_returnsNone()
{
  QCOMPARE(OSXComputer::classifyNavigationGestureButton(kGestureType, true, true, 1.0), kButtonNone);
}

void OSXComputerTests::classifyNavigationGestureButton_nonGestureEvent_returnsNone()
{
  QCOMPARE(OSXComputer::classifyNavigationGestureButton(kCGEventScrollWheel, false, true, 1.0), kButtonNone);
}

void OSXComputerTests::classifyNavigationGestureButton_zeroDelta_returnsNone()
{
  QCOMPARE(OSXComputer::classifyNavigationGestureButton(kGestureType, false, true, 0.0), kButtonNone);
}

QTEST_MAIN(OSXComputerTests)
