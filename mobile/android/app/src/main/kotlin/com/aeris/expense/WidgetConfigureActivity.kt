package com.aeris.expense

import io.flutter.embedding.android.FlutterActivity

/// Launched by Android immediately after the AERIS widget is pinned to the
/// home screen (declared via android:configure in aeris_widget_info.xml).
/// Runs a fresh Flutter engine pinned to the /widget-configure route (see
/// the InitialRoute meta-data in AndroidManifest.xml), which shows a
/// confirmation screen and calls HomeWidget.finishHomeWidgetConfigure().
class WidgetConfigureActivity : FlutterActivity()
