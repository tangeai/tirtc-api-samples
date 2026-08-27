import 'package:flutter/widgets.dart';

abstract final class DemoWidgetKeys {
  static const ValueKey<String> rtcProductTab = ValueKey<String>('tirtc_example_product_tab_rtc');
  static const ValueKey<String> cloudStorageProductTab = ValueKey<String>('tirtc-example-product-tab-ti-cloud-storage');
  static const ValueKey<String> cloudStorageAppIdField = ValueKey<String>(
    'tirtc-example-ti-cloud-storage-app-id-field',
  );
  static const ValueKey<String> cloudStorageEndpointField = ValueKey<String>(
    'tirtc-example-ti-cloud-storage-endpoint-field',
  );
  static const ValueKey<String> cloudStorageTokenField = ValueKey<String>('tirtc-example-ti-cloud-storage-token-field');
  static const ValueKey<String> cloudStorageAudioChannelField = ValueKey<String>(
    'tirtc-example-ti-cloud-storage-audio-channel-field',
  );
  static const ValueKey<String> cloudStorageVideoChannelField = ValueKey<String>(
    'tirtc-example-ti-cloud-storage-video-channel-field',
  );
  static const ValueKey<String> cloudStorageScanButton = ValueKey<String>('tirtc-example-ti-cloud-storage-scan-button');
  static const ValueKey<String> cloudStorageEnterButton = ValueKey<String>(
    'tirtc-example-ti-cloud-storage-enter-button',
  );
  static const ValueKey<String> cloudStorageRecordingsPage = ValueKey<String>(
    'tirtc_example_cloud_storage_recordings_page',
  );
  static const ValueKey<String> cloudStorageCalendarButton = ValueKey<String>(
    'tirtc-example-ti-cloud-storage-calendar-button',
  );
  static const ValueKey<String> cloudStorageDatePickerButton = ValueKey<String>(
    'tirtc-example-ti-cloud-storage-date-picker-button',
  );
  static const ValueKey<String> cloudStorageQueryButton = ValueKey<String>(
    'tirtc-example-ti-cloud-storage-query-button',
  );
  static const ValueKey<String> cloudStorageQueryRetryButton = ValueKey<String>(
    'tirtc-example-ti-cloud-storage-query-retry-button',
  );
  static const ValueKey<String> cloudStorageCalendarMonthPrevious = ValueKey<String>(
    'tirtc-example-ti-cloud-storage-calendar-month-previous',
  );
  static const ValueKey<String> cloudStorageCalendarMonthNext = ValueKey<String>(
    'tirtc-example-ti-cloud-storage-calendar-month-next',
  );
  static const ValueKey<String> cloudStorageCalendarRetryButton = ValueKey<String>(
    'tirtc-example-ti-cloud-storage-calendar-retry-button',
  );
  static ValueKey<String> cloudStorageCalendarDay(String date) =>
      ValueKey<String>('tirtc-example-ti-cloud-storage-calendar-day_$date');
  static const ValueKey<String> cloudStorageSeekSlider = ValueKey<String>('tirtc-example-ti-cloud-storage-seek-slider');
  static const ValueKey<String> cloudStorageSpeedSelector = ValueKey<String>(
    'tirtc-example-ti-cloud-storage-speed-selector',
  );
  static const ValueKey<String> cloudStoragePauseButton = ValueKey<String>(
    'tirtc-example-ti-cloud-storage-pause-button',
  );
  static const ValueKey<String> cloudStorageRecordingButton = ValueKey<String>(
    'tirtc-example-ti-cloud-storage-recording-button',
  );
  static const ValueKey<String> cloudStorageSnapshotButton = ValueKey<String>(
    'tirtc-example-ti-cloud-storage-snapshot-button',
  );
  static const ValueKey<String> cloudStorageGalleryButton = ValueKey<String>(
    'tirtc-example-ti-cloud-storage-gallery-button',
  );
  static const ValueKey<String> cloudStorageAudioVolumeButton = ValueKey<String>(
    'tirtc-example-ti-cloud-storage-audio-volume-button',
  );
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
  static const ValueKey<String> cloudStorageConfigureLogUploadButton = ValueKey<String>(
    'tirtc-example-ti-cloud-storage-configure-log-upload-button',
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
