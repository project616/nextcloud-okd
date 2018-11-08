<?php
$CONFIG = array (
  'log_type' => 'owncloud',
  'logfile' => '/var/log/nextcloud.log',
  'loglevel' => '2',
  'datadirectory' => '/var/www/html/data',
  'updatechecker' => false,
  'check_for_working_htaccess' => false,
  'asset-pipeline.enabled' => false,
  'assetdirectory' => '/var/www/html/asset',
  'installed' => true,
  'apps_paths' => 
  array (
    0 => 
    array (
      'path' => '/var/www/html/apps',
      'url' => '/apps',
      'writable' => true,
    ),
    1 => 
    array (
      'path' => '/var/www/html/apps',
      'url' => '/apps-appstore',
      'writable' => true,
    ),
  ),
);
