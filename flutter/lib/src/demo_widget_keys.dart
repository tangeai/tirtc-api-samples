import 'package:flutter/widgets.dart';

abstract final class DemoWidgetKeys {
  static const ValueKey<String> rtcProductTab = ValueKey<String>('tirtc_example_product_tab_rtc');
  static const ValueKey<String> storeProductTab = ValueKey<String>('tirtc_example_product_tab_store');
  static const ValueKey<String> storeAppIdField = ValueKey<String>('tirtc_example_store_app_id_field');
  static const ValueKey<String> storeEndpointField = ValueKey<String>('tirtc_example_store_endpoint_field');
  static const ValueKey<String> storeTokenField = ValueKey<String>('tirtc_example_store_token_field');
  static const ValueKey<String> storeAudioChannelField = ValueKey<String>('tirtc_example_store_audio_channel_field');
  static const ValueKey<String> storeVideoChannelField = ValueKey<String>('tirtc_example_store_video_channel_field');
  static const ValueKey<String> storeScanButton = ValueKey<String>('tirtc_example_store_scan_button');
  static const ValueKey<String> storeEnterButton = ValueKey<String>('tirtc_example_store_enter_button');
  static const ValueKey<String> storeRecordingsPage = ValueKey<String>('tirtc_example_store_recordings_page');
  static const ValueKey<String> storeCalendarButton = ValueKey<String>('tirtc_example_store_calendar_button');
  static const ValueKey<String> storeDatePickerButton = ValueKey<String>('tirtc_example_store_date_picker_button');
  static const ValueKey<String> storeQueryButton = ValueKey<String>('tirtc_example_store_query_button');
  static const ValueKey<String> storeQueryRetryButton = ValueKey<String>('tirtc_example_store_query_retry_button');
  static const ValueKey<String> storeCalendarMonthPrevious = ValueKey<String>(
    'tirtc_example_store_calendar_month_previous',
  );
  static const ValueKey<String> storeCalendarMonthNext = ValueKey<String>('tirtc_example_store_calendar_month_next');
  static const ValueKey<String> storeCalendarRetryButton = ValueKey<String>(
    'tirtc_example_store_calendar_retry_button',
  );
  static ValueKey<String> storeCalendarDay(String date) => ValueKey<String>('tirtc_example_store_calendar_day_$date');
  static const ValueKey<String> storeSeekSlider = ValueKey<String>('tirtc_example_store_seek_slider');
  static const ValueKey<String> storeSpeedSelector = ValueKey<String>('tirtc_example_store_speed_selector');
  static const ValueKey<String> storePauseButton = ValueKey<String>('tirtc_example_store_pause_button');
  static const ValueKey<String> storeRecordingButton = ValueKey<String>('tirtc_example_store_recording_button');
  static const ValueKey<String> storeSnapshotButton = ValueKey<String>('tirtc_example_store_snapshot_button');
  static const ValueKey<String> storeGalleryButton = ValueKey<String>('tirtc_example_store_gallery_button');
  static const ValueKey<String> storeAudioVolumeButton = ValueKey<String>('tirtc_example_store_audio_volume_button');
  static const ValueKey<String> noticeDialogConfirmButton = ValueKey<String>('tirtc_example_notice_dialog_confirm');
  static const ValueKey<String> playerPage = ValueKey<String>('tirtc_example_player_page');
  static const ValueKey<String> playerCommandButton = ValueKey<String>('tirtc_example_player_command_button');
  static const ValueKey<String> playerLocalAudioButton = ValueKey<String>('tirtc_example_player_local_audio_button');
  static const ValueKey<String> playerAudioVolumeButton = ValueKey<String>('tirtc_example_player_audio_volume_button');
  static const ValueKey<String> streamMessageBubble = ValueKey<String>('tirtc_example_stream_message_bubble');
  static const ValueKey<String> playerLogUploadButton = ValueKey<String>('tirtc_example_player_log_upload_button');
  static const ValueKey<String> playerRecordingButton = ValueKey<String>('tirtc_example_player_recording_button');
  static const ValueKey<String> playerSnapshotButton = ValueKey<String>('tirtc_example_player_snapshot_button');
  static const ValueKey<String> playerGalleryButton = ValueKey<String>('tirtc_example_player_gallery_button');
  static const ValueKey<String> commandPanelSheet = ValueKey<String>('tirtc_example_command_panel_sheet');
  static const ValueKey<String> commandPanelCloseButton = ValueKey<String>('tirtc_example_command_panel_close_button');
  static const ValueKey<String> commandPanelCommandIdField = ValueKey<String>(
    'tirtc_example_command_panel_command_id_field',
  );
  static const ValueKey<String> commandPanelPayloadField = ValueKey<String>(
    'tirtc_example_command_panel_payload_field',
  );
  static const ValueKey<String> commandPanelSendButton = ValueKey<String>('tirtc_example_command_panel_send_button');
  static const ValueKey<String> commandPanelEchoPreset = ValueKey<String>('tirtc_example_command_panel_echo_preset');
  static const ValueKey<String> startDownlinkButton = ValueKey<String>('tirtc_example_start_downlink_button');
  static const ValueKey<String> configureLogUploadButton = ValueKey<String>(
    'tirtc_example_configure_log_upload_button',
  );
  static const ValueKey<String> storeConfigureLogUploadButton = ValueKey<String>(
    'tirtc_example_store_configure_log_upload_button',
  );
  static const ValueKey<String> endpointField = ValueKey<String>('tirtc_example_endpoint_field');
  static const ValueKey<String> appIdField = ValueKey<String>('tirtc_example_app_id_field');
  static const ValueKey<String> remoteIdField = ValueKey<String>('tirtc_example_remote_id_field');
  static const ValueKey<String> audioStreamIdField = ValueKey<String>('tirtc_example_audio_stream_id_field');
  static const ValueKey<String> videoStreamIdField = ValueKey<String>('tirtc_example_video_stream_id_field');
  static const ValueKey<String> tokenField = ValueKey<String>('tirtc_example_token_field');
  static const ValueKey<String> tokenServerAddressField = ValueKey<String>('tirtc_example_token_server_address_field');
  static const ValueKey<String> tokenScanButton = ValueKey<String>('tirtc_example_token_scan_button');
  static const ValueKey<String> downlinkMetricsStatsExpandAction = ValueKey<String>(
    'tirtc_example_downlink_metrics_stats_expand_action',
  );
  static const ValueKey<String> downlinkMetricsStatsCollapseAction = ValueKey<String>(
    'tirtc_example_downlink_metrics_stats_collapse_action',
  );
  static const ValueKey<String> downlinkMetricsStatsPanel = ValueKey<String>(
    'tirtc_example_downlink_metrics_stats_panel',
  );
  static const ValueKey<String> downlinkMetricsMediaParamsText = ValueKey<String>(
    'tirtc_example_downlink_metrics_media_params_text',
  );
  static const ValueKey<String> downlinkMetricsVideoReceiveText = ValueKey<String>(
    'tirtc_example_downlink_metrics_video_receive_text',
  );
  static const ValueKey<String> downlinkMetricsAudioReceiveText = ValueKey<String>(
    'tirtc_example_downlink_metrics_audio_receive_text',
  );
  static const ValueKey<String> downlinkMetricsLatencyStatsText = ValueKey<String>(
    'tirtc_example_downlink_metrics_latency_stats_text',
  );
  static const ValueKey<String> downlinkMetricsStartupText = ValueKey<String>(
    'tirtc_example_downlink_metrics_startup_text',
  );
  static const ValueKey<String> downlinkMetricsStutterText = ValueKey<String>(
    'tirtc_example_downlink_metrics_stutter_text',
  );
  static ValueKey<String> commandPanelEvent(String direction, String commandIdLabel) =>
      ValueKey<String>('tirtc_example_command_panel_event_${direction}_$commandIdLabel');
}
