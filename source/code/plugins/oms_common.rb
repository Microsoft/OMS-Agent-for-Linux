# frozen_string_literal: true

module OMS

  class RetryRequestException < Exception
    # Throw this exception to tell the fluentd engine to retry and
    # inform the output plugin that it is indeed retryable
  end

  class Common
    require 'json'
    require 'yajl'
    require 'net/http'
    require 'net/https'
    require 'time'
    require 'zlib'
    require 'digest'
    require 'date'
    require 'securerandom'
    require 'resolv-replace'
    require 'socket'

    require_relative 'omslog'
    require_relative 'oms_configuration'
    
    @@OSFullName = nil
    @@OSName = nil
    @@OSVersion = nil
    @@Hostname = nil
    @@HostnameFilePath = '/var/opt/microsoft/docker-cimprov/state/containerhostname'
    @@FQDN = nil
    @@InstalledDate = nil
    @@AgentVersion = nil
    @@CurrentTimeZone = nil

    @@tzMapping = {
      'Australia/Darwin' => 'AUS Central Standard Time',
      'Australia/Sydney' => 'AUS Eastern Standard Time',
      'Australia/Melbourne' => 'AUS Eastern Standard Time',
      'Asia/Kabul' => 'Afghanistan Standard Time',
      'America/Anchorage' => 'Alaskan Standard Time',
      'America/Juneau' => 'Alaskan Standard Time',
      'America/Metlakatla' => 'Alaskan Standard Time',
      'America/Nome' => 'Alaskan Standard Time',
      'America/Sitka' => 'Alaskan Standard Time',
      'America/Yakutat' => 'Alaskan Standard Time',
      'Asia/Riyadh' => 'Arab Standard Time',
      'Asia/Bahrain' => 'Arab Standard Time',
      'Asia/Kuwait' => 'Arab Standard Time',
      'Asia/Qatar' => 'Arab Standard Time',
      'Asia/Aden' => 'Arab Standard Time',
      'Asia/Dubai' => 'Arabian Standard Time',
      'Asia/Muscat' => 'Arabian Standard Time',
      'Etc/GMT-4' => 'Arabian Standard Time',
      'Asia/Baghdad' => 'Arabic Standard Time',
      'America/Buenos_Aires' => 'Argentina Standard Time',
      'America/Argentina/La_Rioja' => 'Argentina Standard Time',
      'America/Argentina/Rio_Gallegos' => 'Argentina Standard Time',
      'America/Argentina/Salta' => 'Argentina Standard Time',
      'America/Argentina/San_Juan' => 'Argentina Standard Time',
      'America/Argentina/San_Luis' => 'Argentina Standard Time',
      'America/Argentina/Tucuman' => 'Argentina Standard Time',
      'America/Argentina/Ushuaia' => 'Argentina Standard Time',
      'America/Catamarca' => 'Argentina Standard Time',
      'America/Cordoba' => 'Argentina Standard Time',
      'America/Jujuy' => 'Argentina Standard Time',
      'America/Mendoza' => 'Argentina Standard Time',
      'America/Halifax' => 'Atlantic Standard Time',
      'Atlantic/Bermuda' => 'Atlantic Standard Time',
      'America/Glace_Bay' => 'Atlantic Standard Time',
      'America/Goose_Bay' => 'Atlantic Standard Time',
      'America/Moncton' => 'Atlantic Standard Time',
      'America/Thule' => 'Atlantic Standard Time',
      'Asia/Baku' => 'Azerbaijan Standard Time',
      'Atlantic/Azores' => 'Azores Standard Time',
      'America/Scoresbysund' => 'Azores Standard Time',
      'America/Bahia' => 'Bahia Standard Time',
      'Asia/Dhaka' => 'Bangladesh Standard Time',
      'Asia/Thimphu' => 'Bangladesh Standard Time',
      'Europe/Minsk' => 'Belarus Standard Time',
      'America/Regina' => 'Canada Central Standard Time',
      'America/Swift_Current' => 'Canada Central Standard Time',
      'Atlantic/Cape_Verde' => 'Cape Verde Standard Time',
      'Etc/GMT+1' => 'Cape Verde Standard Time',
      'Asia/Yerevan' => 'Caucasus Standard Time',
      'Australia/Adelaide' => 'Cen. Australia Standard Time',
      'Australia/Broken_Hill' => 'Cen. Australia Standard Time',
      'America/Guatemala' => 'Central America Standard Time',
      'America/Belize' => 'Central America Standard Time',
      'America/Costa_Rica' => 'Central America Standard Time',
      'Pacific/Galapagos' => 'Central America Standard Time',
      'America/Tegucigalpa' => 'Central America Standard Time',
      'America/Managua' => 'Central America Standard Time',
      'America/El_Salvador' => 'Central America Standard Time',
      'Etc/GMT+6' => 'Central America Standard Time',
      'Asia/Almaty' => 'Central Asia Standard Time',
      'Antarctica/Vostok' => 'Central Asia Standard Time',
      'Indian/Chagos' => 'Central Asia Standard Time',
      'Asia/Bishkek' => 'Central Asia Standard Time',
      'Asia/Qyzylorda' => 'Central Asia Standard Time',
      'Etc/GMT-6' => 'Central Asia Standard Time',
      'America/Cuiaba' => 'Central Brazilian Standard Time',
      'America/Campo_Grande' => 'Central Brazilian Standard Time',
      'Europe/Budapest' => 'Central Europe Standard Time',
      'Europe/Tirane' => 'Central Europe Standard Time',
      'Europe/Prague' => 'Central Europe Standard Time',
      'Europe/Podgorica' => 'Central Europe Standard Time',
      'Europe/Belgrade' => 'Central Europe Standard Time',
      'Europe/Ljubljana' => 'Central Europe Standard Time',
      'Europe/Bratislava' => 'Central Europe Standard Time',
      'Europe/Warsaw' => 'Central European Standard Time',
      'Europe/Sarajevo' => 'Central European Standard Time',
      'Europe/Zagreb' => 'Central European Standard Time',
      'Europe/Skopje' => 'Central European Standard Time',
      'Pacific/Guadalcanal' => 'Central Pacific Standard Time',
      'Antarctica/Macquarie' => 'Central Pacific Standard Time',
      'Pacific/Ponape' => 'Central Pacific Standard Time',
      'Pacific/Kosrae' => 'Central Pacific Standard Time',
      'Pacific/Noumea' => 'Central Pacific Standard Time',
      'Pacific/Norfolk' => 'Central Pacific Standard Time',
      'Pacific/Bougainville' => 'Central Pacific Standard Time',
      'Pacific/Efate' => 'Central Pacific Standard Time',
      'Etc/GMT-11' => 'Central Pacific Standard Time',
      'America/Chicago' => 'Central Standard Time',
      'America/Winnipeg' => 'Central Standard Time',
      'America/Rainy_River' => 'Central Standard Time',
      'America/Rankin_Inlet' => 'Central Standard Time',
      'America/Resolute' => 'Central Standard Time',
      'America/Matamoros' => 'Central Standard Time',
      'America/Indiana/Knox' => 'Central Standard Time',
      'America/Indiana/Tell_City' => 'Central Standard Time',
      'America/Menominee' => 'Central Standard Time',
      'America/North_Dakota/Beulah' => 'Central Standard Time',
      'America/North_Dakota/Center' => 'Central Standard Time',
      'America/North_Dakota/New_Salem' => 'Central Standard Time',
      'CST6CDT' => 'Central Standard Time',
      'America/Mexico_City' => 'Central Standard Time (Mexico)',
      'America/Bahia_Banderas' => 'Central Standard Time (Mexico)',
      'America/Merida' => 'Central Standard Time (Mexico)',
      'America/Monterrey' => 'Central Standard Time (Mexico)',
      'Asia/Shanghai' => 'China Standard Time',
      'Asia/Chongqing' => 'China Standard Time',
      'Asia/Harbin' => 'China Standard Time',
      'Asia/Kashgar' => 'China Standard Time',
      'Asia/Urumqi' => 'China Standard Time',
      'Asia/Hong_Kong' => 'China Standard Time',
      'Asia/Macau' => 'China Standard Time',
      'Etc/GMT+12' => 'Dateline Standard Time',
      'Africa/Nairobi' => 'E. Africa Standard Time',
      'Antarctica/Syowa' => 'E. Africa Standard Time',
      'Africa/Djibouti' => 'E. Africa Standard Time',
      'Africa/Asmera' => 'E. Africa Standard Time',
      'Africa/Addis_Ababa' => 'E. Africa Standard Time',
      'Indian/Comoro' => 'E. Africa Standard Time',
      'Indian/Antananarivo' => 'E. Africa Standard Time',
      'Africa/Khartoum' => 'E. Africa Standard Time',
      'Africa/Mogadishu' => 'E. Africa Standard Time',
      'Africa/Juba' => 'E. Africa Standard Time',
      'Africa/Dar_es_Salaam' => 'E. Africa Standard Time',
      'Africa/Kampala' => 'E. Africa Standard Time',
      'Indian/Mayotte' => 'E. Africa Standard Time',
      'Etc/GMT-3' => 'E. Africa Standard Time',
      'Australia/Brisbane' => 'E. Australia Standard Time',
      'Australia/Lindeman' => 'E. Australia Standard Time',
      'Europe/Chisinau' => 'E. Europe Standard Time',
      'America/Sao_Paulo' => 'E. South America Standard Time',
      'America/New_York' => 'Eastern Standard Time',
      'America/Nassau' => 'Eastern Standard Time',
      'America/Toronto' => 'Eastern Standard Time',
      'America/Iqaluit' => 'Eastern Standard Time',
      'America/Montreal' => 'Eastern Standard Time',
      'America/Nipigon' => 'Eastern Standard Time',
      'America/Pangnirtung' => 'Eastern Standard Time',
      'America/Thunder_Bay' => 'Eastern Standard Time',
      'America/Havana' => 'Eastern Standard Time',
      'America/Port-au-Prince' => 'Eastern Standard Time',
      'America/Detroit' => 'Eastern Standard Time',
      'America/Indiana/Petersburg' => 'Eastern Standard Time',
      'America/Indiana/Vincennes' => 'Eastern Standard Time',
      'America/Indiana/Winamac' => 'Eastern Standard Time',
      'America/Kentucky/Monticello' => 'Eastern Standard Time',
      'America/Louisville' => 'Eastern Standard Time',
      'EST5EDT' => 'Eastern Standard Time',
      'America/Cancun' => 'Eastern Standard Time (Mexico)',
      'Africa/Cairo' => 'Egypt Standard Time',
      'Asia/Gaza' => 'Egypt Standard Time',
      'Asia/Hebron' => 'Egypt Standard Time',
      'Asia/Yekaterinburg' => 'Ekaterinburg Standard Time',
      'Europe/Kiev' => 'FLE Standard Time',
      'Europe/Mariehamn' => 'FLE Standard Time',
      'Europe/Sofia' => 'FLE Standard Time',
      'Europe/Tallinn' => 'FLE Standard Time',
      'Europe/Helsinki' => 'FLE Standard Time',
      'Europe/Vilnius' => 'FLE Standard Time',
      'Europe/Riga' => 'FLE Standard Time',
      'Europe/Uzhgorod' => 'FLE Standard Time',
      'Europe/Zaporozhye' => 'FLE Standard Time',
      'Pacific/Fiji' => 'Fiji Standard Time',
      'Europe/London' => 'GMT Standard Time',
      'Atlantic/Canary' => 'GMT Standard Time',
      'Atlantic/Faeroe' => 'GMT Standard Time',
      'Europe/Guernsey' => 'GMT Standard Time',
      'Europe/Dublin' => 'GMT Standard Time',
      'Europe/Isle_of_Man' => 'GMT Standard Time',
      'Europe/Jersey' => 'GMT Standard Time',
      'Europe/Lisbon' => 'GMT Standard Time',
      'Atlantic/Madeira' => 'GMT Standard Time',
      'Europe/Bucharest' => 'GTB Standard Time',
      'Asia/Nicosia' => 'GTB Standard Time',
      'Europe/Athens' => 'GTB Standard Time',
      'Asia/Tbilisi' => 'Georgian Standard Time',
      'America/Godthab' => 'Greenland Standard Time',
      'Atlantic/Reykjavik' => 'Greenwich Standard Time',
      'Africa/Ouagadougou' => 'Greenwich Standard Time',
      'Africa/Abidjan' => 'Greenwich Standard Time',
      'Africa/Accra' => 'Greenwich Standard Time',
      'Africa/Banjul' => 'Greenwich Standard Time',
      'Africa/Conakry' => 'Greenwich Standard Time',
      'Africa/Bissau' => 'Greenwich Standard Time',
      'Africa/Monrovia' => 'Greenwich Standard Time',
      'Africa/Bamako' => 'Greenwich Standard Time',
      'Africa/Nouakchott' => 'Greenwich Standard Time',
      'Atlantic/St_Helena' => 'Greenwich Standard Time',
      'Africa/Freetown' => 'Greenwich Standard Time',
      'Africa/Dakar' => 'Greenwich Standard Time',
      'Africa/Sao_Tome' => 'Greenwich Standard Time',
      'Africa/Lome' => 'Greenwich Standard Time',
      'Pacific/Honolulu' => 'Hawaiian Standard Time',
      'Pacific/Rarotonga' => 'Hawaiian Standard Time',
      'Pacific/Tahiti' => 'Hawaiian Standard Time',
      'Pacific/Johnston' => 'Hawaiian Standard Time',
      'Etc/GMT+10' => 'Hawaiian Standard Time',
      'Asia/Calcutta' => 'India Standard Time',
      'Asia/Tehran' => 'Iran Standard Time',
      'Asia/Jerusalem' => 'Israel Standard Time',
      'Asia/Amman' => 'Jordan Standard Time',
      'Europe/Kaliningrad' => 'Kaliningrad Standard Time',
      'Asia/Seoul' => 'Korea Standard Time',
      'Africa/Tripoli' => 'Libya Standard Time',
      'Pacific/Kiritimati' => 'Line Islands Standard Time',
      'Etc/GMT-14' => 'Line Islands Standard Time',
      'Asia/Magadan' => 'Magadan Standard Time',
      'Indian/Mauritius' => 'Mauritius Standard Time',
      'Indian/Reunion' => 'Mauritius Standard Time',
      'Indian/Mahe' => 'Mauritius Standard Time',
      'Asia/Beirut' => 'Middle East Standard Time',
      'America/Montevideo' => 'Montevideo Standard Time',
      'Africa/Casablanca' => 'Morocco Standard Time',
      'Africa/El_Aaiun' => 'Morocco Standard Time',
      'America/Denver' => 'Mountain Standard Time',
      'America/Edmonton' => 'Mountain Standard Time',
      'America/Cambridge_Bay' => 'Mountain Standard Time',
      'America/Inuvik' => 'Mountain Standard Time',
      'America/Yellowknife' => 'Mountain Standard Time',
      'America/Ojinaga' => 'Mountain Standard Time',
      'America/Boise' => 'Mountain Standard Time',
      'MST7MDT' => 'Mountain Standard Time',
      'America/Chihuahua' => 'Mountain Standard Time (Mexico)',
      'America/Mazatlan' => 'Mountain Standard Time (Mexico)',
      'Asia/Rangoon' => 'Myanmar Standard Time',
      'Indian/Cocos' => 'Myanmar Standard Time',
      'Asia/Novosibirsk' => 'N. Central Asia Standard Time',
      'Asia/Omsk' => 'N. Central Asia Standard Time',
      'Africa/Windhoek' => 'Namibia Standard Time',
      'Asia/Katmandu' => 'Nepal Standard Time',
      'Pacific/Auckland' => 'New Zealand Standard Time',
      'Antarctica/McMurdo' => 'New Zealand Standard Time',
      'America/St_Johns' => 'Newfoundland Standard Time',
      'Asia/Irkutsk' => 'North Asia East Standard Time',
      'Asia/Krasnoyarsk' => 'North Asia Standard Time',
      'Asia/Novokuznetsk' => 'North Asia Standard Time',
      'Asia/Pyongyang' => 'North Korea Standard Time',
      'America/Santiago' => 'Pacific SA Standard Time',
      'Antarctica/Palmer' => 'Pacific SA Standard Time',
      'America/Los_Angeles' => 'Pacific Standard Time',
      'America/Vancouver' => 'Pacific Standard Time',
      'America/Dawson' => 'Pacific Standard Time',
      'America/Whitehorse' => 'Pacific Standard Time',
      'America/Tijuana' => 'Pacific Standard Time',
      'America/Santa_Isabel' => 'Pacific Standard Time',
      'PST8PDT' => 'Pacific Standard Time',
      'Asia/Karachi' => 'Pakistan Standard Time',
      'America/Asuncion' => 'Paraguay Standard Time',
      'Europe/Paris' => 'Romance Standard Time',
      'Europe/Brussels' => 'Romance Standard Time',
      'Europe/Copenhagen' => 'Romance Standard Time',
      'Europe/Madrid' => 'Romance Standard Time',
      'Africa/Ceuta' => 'Romance Standard Time',
      'Asia/Srednekolymsk' => 'Russia Time Zone 10',
      'Asia/Kamchatka' => 'Russia Time Zone 11',
      'Asia/Anadyr' => 'Russia Time Zone 11',
      'Europe/Samara' => 'Russia Time Zone 3',
      'Europe/Moscow' => 'Russian Standard Time',
      'Europe/Simferopol' => 'Russian Standard Time',
      'Europe/Volgograd' => 'Russian Standard Time',
      'America/Cayenne' => 'SA Eastern Standard Time',
      'Antarctica/Rothera' => 'SA Eastern Standard Time',
      'America/Fortaleza' => 'SA Eastern Standard Time',
      'America/Araguaina' => 'SA Eastern Standard Time',
      'America/Belem' => 'SA Eastern Standard Time',
      'America/Maceio' => 'SA Eastern Standard Time',
      'America/Recife' => 'SA Eastern Standard Time',
      'America/Santarem' => 'SA Eastern Standard Time',
      'Atlantic/Stanley' => 'SA Eastern Standard Time',
      'America/Paramaribo' => 'SA Eastern Standard Time',
      'Etc/GMT+3' => 'SA Eastern Standard Time',
      'America/Bogota' => 'SA Pacific Standard Time',
      'America/Rio_Branco' => 'SA Pacific Standard Time',
      'America/Eirunepe' => 'SA Pacific Standard Time',
      'America/Coral_Harbour' => 'SA Pacific Standard Time',
      'Pacific/Easter' => 'SA Pacific Standard Time',
      'America/Guayaquil' => 'SA Pacific Standard Time',
      'America/Jamaica' => 'SA Pacific Standard Time',
      'America/Cayman' => 'SA Pacific Standard Time',
      'America/Panama' => 'SA Pacific Standard Time',
      'America/Lima' => 'SA Pacific Standard Time',
      'Etc/GMT+5' => 'SA Pacific Standard Time',
      'America/La_Paz' => 'SA Western Standard Time',
      'America/Antigua' => 'SA Western Standard Time',
      'America/Anguilla' => 'SA Western Standard Time',
      'America/Aruba' => 'SA Western Standard Time',
      'America/Barbados' => 'SA Western Standard Time',
      'America/St_Barthelemy' => 'SA Western Standard Time',
      'America/Kralendijk' => 'SA Western Standard Time',
      'America/Manaus' => 'SA Western Standard Time',
      'America/Boa_Vista' => 'SA Western Standard Time',
      'America/Porto_Velho' => 'SA Western Standard Time',
      'America/Blanc-Sablon' => 'SA Western Standard Time',
      'America/Curacao' => 'SA Western Standard Time',
      'America/Dominica' => 'SA Western Standard Time',
      'America/Santo_Domingo' => 'SA Western Standard Time',
      'America/Grenada' => 'SA Western Standard Time',
      'America/Guadeloupe' => 'SA Western Standard Time',
      'America/Guyana' => 'SA Western Standard Time',
      'America/St_Kitts' => 'SA Western Standard Time',
      'America/St_Lucia' => 'SA Western Standard Time',
      'America/Marigot' => 'SA Western Standard Time',
      'America/Martinique' => 'SA Western Standard Time',
      'America/Montserrat' => 'SA Western Standard Time',
      'America/Puerto_Rico' => 'SA Western Standard Time',
      'America/Lower_Princes' => 'SA Western Standard Time',
      'America/Grand_Turk' => 'SA Western Standard Time',
      'America/Port_of_Spain' => 'SA Western Standard Time',
      'America/St_Vincent' => 'SA Western Standard Time',
      'America/Tortola' => 'SA Western Standard Time',
      'America/St_Thomas' => 'SA Western Standard Time',
      'Etc/GMT+4' => 'SA Western Standard Time',
      'Asia/Bangkok' => 'SE Asia Standard Time',
      'Antarctica/Davis' => 'SE Asia Standard Time',
      'Indian/Christmas' => 'SE Asia Standard Time',
      'Asia/Jakarta' => 'SE Asia Standard Time',
      'Asia/Pontianak' => 'SE Asia Standard Time',
      'Asia/Phnom_Penh' => 'SE Asia Standard Time',
      'Asia/Vientiane' => 'SE Asia Standard Time',
      'Asia/Hovd' => 'SE Asia Standard Time',
      'Asia/Saigon' => 'SE Asia Standard Time',
      'Etc/GMT-7' => 'SE Asia Standard Time',
      'Pacific/Apia' => 'Samoa Standard Time',
      'Asia/Singapore' => 'Singapore Standard Time',
      'Asia/Brunei' => 'Singapore Standard Time',
      'Asia/Makassar' => 'Singapore Standard Time',
      'Asia/Kuala_Lumpur' => 'Singapore Standard Time',
      'Asia/Kuching' => 'Singapore Standard Time',
      'Asia/Manila' => 'Singapore Standard Time',
      'Etc/GMT-8' => 'Singapore Standard Time',
      'Africa/Johannesburg' => 'South Africa Standard Time',
      'Africa/Bujumbura' => 'South Africa Standard Time',
      'Africa/Gaborone' => 'South Africa Standard Time',
      'Africa/Lubumbashi' => 'South Africa Standard Time',
      'Africa/Maseru' => 'South Africa Standard Time',
      'Africa/Blantyre' => 'South Africa Standard Time',
      'Africa/Maputo' => 'South Africa Standard Time',
      'Africa/Kigali' => 'South Africa Standard Time',
      'Africa/Mbabane' => 'South Africa Standard Time',
      'Africa/Lusaka' => 'South Africa Standard Time',
      'Africa/Harare' => 'South Africa Standard Time',
      'Etc/GMT-2' => 'South Africa Standard Time',
      'Asia/Colombo' => 'Sri Lanka Standard Time',
      'Asia/Damascus' => 'Syria Standard Time',
      'Asia/Taipei' => 'Taipei Standard Time',
      'Australia/Hobart' => 'Tasmania Standard Time',
      'Australia/Currie' => 'Tasmania Standard Time',
      'Asia/Tokyo' => 'Tokyo Standard Time',
      'Asia/Jayapura' => 'Tokyo Standard Time',
      'Pacific/Palau' => 'Tokyo Standard Time',
      'Asia/Dili' => 'Tokyo Standard Time',
      'Etc/GMT-9' => 'Tokyo Standard Time',
      'Pacific/Tongatapu' => 'Tonga Standard Time',
      'Pacific/Enderbury' => 'Tonga Standard Time',
      'Pacific/Fakaofo' => 'Tonga Standard Time',
      'Etc/GMT-13' => 'Tonga Standard Time',
      'Europe/Istanbul' => 'Turkey Standard Time',
      'America/Indianapolis' => 'US Eastern Standard Time',
      'America/Indiana/Marengo' => 'US Eastern Standard Time',
      'America/Indiana/Vevay' => 'US Eastern Standard Time',
      'America/Phoenix' => 'US Mountain Standard Time',
      'America/Dawson_Creek' => 'US Mountain Standard Time',
      'America/Creston' => 'US Mountain Standard Time',
      'America/Fort_Nelson' => 'US Mountain Standard Time',
      'America/Hermosillo' => 'US Mountain Standard Time',
      'Etc/GMT+7' => 'US Mountain Standard Time',
      'Etc/GMT' => 'UTC',
      'Etc/UTC' => 'UTC',
      'America/Danmarkshavn' => 'UTC',
      'Etc/GMT-12' => 'UTC+12',
      'Pacific/Tarawa' => 'UTC+12',
      'Pacific/Majuro' => 'UTC+12',
      'Pacific/Kwajalein' => 'UTC+12',
      'Pacific/Nauru' => 'UTC+12',
      'Pacific/Funafuti' => 'UTC+12',
      'Pacific/Wake' => 'UTC+12',
      'Pacific/Wallis' => 'UTC+12',
      'Etc/GMT+2' => 'UTC-02',
      'America/Noronha' => 'UTC-02',
      'Atlantic/South_Georgia' => 'UTC-02',
      'Etc/GMT+11' => 'UTC-11',
      'Pacific/Pago_Pago' => 'UTC-11',
      'Pacific/Niue' => 'UTC-11',
      'Pacific/Midway' => 'UTC-11',
      'Asia/Ulaanbaatar' => 'Ulaanbaatar Standard Time',
      'Asia/Choibalsan' => 'Ulaanbaatar Standard Time',
      'America/Caracas' => 'Venezuela Standard Time',
      'Asia/Vladivostok' => 'Vladivostok Standard Time',
      'Asia/Sakhalin' => 'Vladivostok Standard Time',
      'Asia/Ust-Nera' => 'Vladivostok Standard Time',
      'Australia/Perth' => 'W. Australia Standard Time',
      'Antarctica/Casey' => 'W. Australia Standard Time',
      'Africa/Lagos' => 'W. Central Africa Standard Time',
      'Africa/Luanda' => 'W. Central Africa Standard Time',
      'Africa/Porto-Novo' => 'W. Central Africa Standard Time',
      'Africa/Kinshasa' => 'W. Central Africa Standard Time',
      'Africa/Bangui' => 'W. Central Africa Standard Time',
      'Africa/Brazzaville' => 'W. Central Africa Standard Time',
      'Africa/Douala' => 'W. Central Africa Standard Time',
      'Africa/Algiers' => 'W. Central Africa Standard Time',
      'Africa/Libreville' => 'W. Central Africa Standard Time',
      'Africa/Malabo' => 'W. Central Africa Standard Time',
      'Africa/Niamey' => 'W. Central Africa Standard Time',
      'Africa/Ndjamena' => 'W. Central Africa Standard Time',
      'Africa/Tunis' => 'W. Central Africa Standard Time',
      'Etc/GMT-1' => 'W. Central Africa Standard Time',
      'Europe/Berlin' => 'W. Europe Standard Time',
      'Europe/Andorra' => 'W. Europe Standard Time',
      'Europe/Vienna' => 'W. Europe Standard Time',
      'Europe/Zurich' => 'W. Europe Standard Time',
      'Europe/Busingen' => 'W. Europe Standard Time',
      'Europe/Gibraltar' => 'W. Europe Standard Time',
      'Europe/Rome' => 'W. Europe Standard Time',
      'Europe/Vaduz' => 'W. Europe Standard Time',
      'Europe/Luxembourg' => 'W. Europe Standard Time',
      'Europe/Monaco' => 'W. Europe Standard Time',
      'Europe/Malta' => 'W. Europe Standard Time',
      'Europe/Amsterdam' => 'W. Europe Standard Time',
      'Europe/Oslo' => 'W. Europe Standard Time',
      'Europe/Stockholm' => 'W. Europe Standard Time',
      'Arctic/Longyearbyen' => 'W. Europe Standard Time',
      'Europe/San_Marino' => 'W. Europe Standard Time',
      'Europe/Vatican' => 'W. Europe Standard Time',
      'Asia/Tashkent' => 'West Asia Standard Time',
      'Antarctica/Mawson' => 'West Asia Standard Time',
      'Asia/Oral' => 'West Asia Standard Time',
      'Asia/Aqtau' => 'West Asia Standard Time',
      'Asia/Aqtobe' => 'West Asia Standard Time',
      'Indian/Maldives' => 'West Asia Standard Time',
      'Indian/Kerguelen' => 'West Asia Standard Time',
      'Asia/Dushanbe' => 'West Asia Standard Time',
      'Asia/Ashgabat' => 'West Asia Standard Time',
      'Asia/Samarkand' => 'West Asia Standard Time',
      'Etc/GMT-5' => 'West Asia Standard Time',
      'Pacific/Port_Moresby' => 'West Pacific Standard Time',
      'Antarctica/DumontDUrville' => 'West Pacific Standard Time',
      'Pacific/Truk' => 'West Pacific Standard Time',
      'Pacific/Guam' => 'West Pacific Standard Time',
      'Pacific/Saipan' => 'West Pacific Standard Time',
      'Etc/GMT-10' => 'West Pacific Standard Time',
      'Asia/Yakutsk' => 'Yakutsk Standard Time',
      'Asia/Chita' => 'Yakutsk Standard Time',
      'Asia/Khandyga' => 'Yakutsk Standard Time'
    }

    @@tzLocalTimePath = '/etc/localtime'
    @@tzBaseFolder = '/usr/share/zoneinfo/'
    @@tzRightFolder = 'right/'

    class << self
      # get the unified timezone id by absolute file path of the timezone file
      # file path: the absolute path of the file
      def get_unified_timezoneid(filepath)
        # remove the baseFolder path
        tzID = filepath[@@tzBaseFolder.length..-1] if filepath.start_with?(@@tzBaseFolder)

        return 'Unknown' if tzID.nil?

        # if the rest starts with 'right/', remove it to unify the format
        tzID = tzID[@@tzRightFolder.length..-1] if tzID.start_with?(@@tzRightFolder)
        
        return tzID
      end # end get_unified_timezoneid

      def get_current_timezone
        return @@CurrentTimeZone if !@@CurrentTimeZone.nil?

        tzID = 'Unknown'
        
        begin
          # if /etc/localtime is a symlink, check the link file's path
          if File.symlink?(@@tzLocalTimePath)
            symlinkpath = File.absolute_path(File.readlink(@@tzLocalTimePath), File.dirname(@@tzLocalTimePath))
            tzID = get_unified_timezoneid(symlinkpath)
            
            # look for the entry in the timezone mapping
            if @@tzMapping.has_key?(tzID)
              @@CurrentTimeZone = @@tzMapping[tzID]
              return @@CurrentTimeZone
            end
          end

          # calculate the hash of /etc/locatime
          hashsum = Digest::SHA256.file(@@tzLocalTimePath).hexdigest

          # looks for a file in the /usr/share/zoneinfo/, which is identical to /etc/localtime. use the file name as the timezone
          Dir.glob("#{@@tzBaseFolder}**/*") { |filepath|
            # find all the files whose SHA256 is the same as the /etc/localtime
            if File.file? filepath and Digest::SHA256.file(filepath).hexdigest == hashsum
              tzID = get_unified_timezoneid(filepath)

              # look for the entry in the timezone mapping
              if @@tzMapping.has_key?(tzID)
                @@CurrentTimeZone = @@tzMapping[tzID]
                return @@CurrentTimeZone
              end
            end
          }
        rescue => error
          OMS::Log.error_once("Unable to get the current time zone: #{error}")
        end

        # assign the tzID if the corresponding Windows Time Zone is not found
        @@CurrentTimeZone = tzID if @@CurrentTimeZone.nil?

        return @@CurrentTimeZone
      end # end get_current_timezone

      def get_os_full_name(conf_path = "/etc/opt/microsoft/scx/conf/scx-release")
        return @@OSFullName if !@@OSFullName.nil?

        if File.file?(conf_path)
          conf = File.read(conf_path)
          os_full_name = conf[/OSFullName=(.*?)\n/, 1]
          if os_full_name and os_full_name.size
            @@OSFullName = os_full_name
          end
        end
        return @@OSFullName
      end

      def get_os_name(conf_path = "/etc/opt/microsoft/scx/conf/scx-release")
        return @@OSName if !@@OSName.nil?

        if File.file?(conf_path)
          conf = File.read(conf_path)
          os_name = conf[/OSName=(.*?)\n/, 1]
          if os_name and os_name.size
            @@OSName = os_name
          end
        end
        return @@OSName
      end

      def get_os_version(conf_path = "/etc/opt/microsoft/scx/conf/scx-release")
        return @@OSVersion if !@@OSVersion.nil?

        if File.file?(conf_path)
          conf = File.read(conf_path)
          os_version = conf[/OSVersion=(.*?)\n/, 1]
          if os_version and os_version.size
            @@OSVersion = os_version
          end
        end
        return @@OSVersion
      end

      def get_hostname
        return @@Hostname if !@@Hostname.nil?

        # Issue:
        #   When omsagent runs inside a container, gethostname returns the hostname of the container (random name)
        #   not the actual machine hostname.
        #   One way to solve this problem is to set the container hostname same as machine name, but this is not
        #   possible when host-machine is a private VM inside a cluster.
        # Solution:
        #   Share/mount ‘/etc/hostname’ as '/var/opt/microsoft/omsagent/state/containername' with container and
        #   omsagent will read hostname from shared file.

        begin
          if File.exist?(@@HostnameFilePath) && File.readable?(@@HostnameFilePath)
            @@Hostname = File.read(@@HostnameFilePath).strip
            return @@Hostname
          end
        rescue => error
          OMS::Log.warn_once("Unable to read the hostname from #{@@HostnameFilePath}: #{error}")
        end

        begin
          hostname = Socket.gethostname.split(".")[0]
        rescue => error
          OMS::Log.error_once("Unable to get the Host Name: #{error}")
        else
          @@Hostname = hostname
        end
        return @@Hostname
      end

      def get_fully_qualified_domain_name
        return @@FQDN unless @@FQDN.nil?

        begin
          fqdn = Socket.gethostbyname(Socket.gethostname)[0]
        rescue => error
          OMS::Log.error_once("Unable to get the FQDN: #{error}")
        else
          @@FQDN = fqdn
        end
        return @@FQDN
      end

      def get_private_ips
        begin
          # Unlike Syslog which could be up to 10K EPS, HB is 1 EPM which obviates need for caching
          addr_infos = Socket.ip_address_list
        rescue => error
          OMS::Log.error_once("Unable to get private IPs: #{error}")
          return [].to_json
        end
    
        private_ipv4 = addr_infos.select( &:ipv4_private? )      # RFC 1918: {10/8, 172.16/12, 192.168/16}
        private_ipv6 = addr_infos.select( &:ipv6_unique_local? ) # RFC 4193: {fc00::/7}

        return (private_ipv4 + private_ipv6).map( &:inspect_sockaddr ).to_json
      end

      def get_installed_date(conf_path = "/etc/opt/microsoft/omsagent/sysconf/installinfo.txt")
        return @@InstalledDate if !@@InstalledDate.nil?

        if File.file?(conf_path)
          conf = File.read(conf_path)
          installed_date = conf[/(.*)\n(.*)/, 2]
          if installed_date and installed_date.size
            begin
              Time.parse(installed_date)
            rescue ArgumentError
              OMS::Log.error_once("Invalid install date: #{installed_date}")
            else
              @@InstalledDate = installed_date
            end
          end
        end
        return @@InstalledDate
      end

      def get_agent_version(conf_path = "/etc/opt/microsoft/omsagent/sysconf/installinfo.txt")
        return @@AgentVersion if !@@AgentVersion.nil?

        if File.file?(conf_path)
          conf = File.read(conf_path)
          agent_version = conf[/([\d]+\.[\d]+\.[\d]+-[\d]+)\s.*\n/, 1]
          if agent_version and agent_version.size
            @@AgentVersion = agent_version
          end
        end

        return @@AgentVersion.nil? ? '0.0.0-0': @@AgentVersion
      end

      def fast_utc_to_iso8601_format(utctime, fraction_digits=3)
        utctime.strftime("%FT%T.%#{fraction_digits}NZ")
      end

      def format_time(time)
        Time.at(time).utc.iso8601(3) # UTC with milliseconds
      end

      def format_time_str(time)
        DateTime.parse(time).strftime("%FT%H:%M:%S.%3NZ")
      end

      def create_error_tag(tag)
        "ERROR::#{tag}::"
      end

      # create an HTTP object which uses HTTPS
      def create_secure_http(uri, proxy={})
        if proxy.empty?
          http = Net::HTTP.new( uri.host, uri.port )
        else
          http = Net::HTTP.new( uri.host, uri.port,
                                proxy[:addr], proxy[:port], proxy[:user], proxy[:pass])
        end
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.open_timeout = 30
        return http
      end # create_secure_http

      # create an HTTP object to ODS
      def create_ods_http(ods_uri, proxy={})
        http = create_secure_http(ods_uri, proxy)
        http.cert = Configuration.cert
        http.key = Configuration.key
        return http
      end # create_ods_http

      # create an HTTPRequest object to ODS
      # parameters:
      #   path: string. path of the request
      #   record: Hash. body of the request
      #   compress: bool. Whether the body of the request should be compressed
      #   extra_header: Hash. extra HTTP headers
      #   serializer: method. serializer of the record
      # returns:
      #   HTTPRequest. request to ODS
      def create_ods_request(path, record, compress, extra_headers=nil, serializer=method(:parse_json_record_encoding))
        headers = extra_headers.nil? ? {} : extra_headers

        azure_resource_id = OMS::Configuration.azure_resource_id
        if !azure_resource_id.to_s.empty?
          headers[OMS::CaseSensitiveString.new("x-ms-AzureResourceId")] = azure_resource_id
        end

        azure_region = OMS::Configuration.azure_region if defined?(OMS::Configuration.azure_region)
        if !azure_region.to_s.empty?
          headers[OMS::CaseSensitiveString.new("x-ms-AzureRegion")] = azure_region
        end
        
        omscloud_id = OMS::Configuration.omscloud_id
        if !omscloud_id.to_s.empty?
          headers[OMS::CaseSensitiveString.new("x-ms-OMSCloudId")] = omscloud_id
        end
        
        uuid = OMS::Configuration.uuid
        if !uuid.to_s.empty?
          headers[OMS::CaseSensitiveString.new("x-ms-UUID")] = uuid
        end
 
        headers[OMS::CaseSensitiveString.new("X-Request-ID")] = SecureRandom.uuid

        headers["Content-Type"] = "application/json"
        if compress == true
          headers["Content-Encoding"] = "deflate"
        end

        headers["User-Agent"] = "LinuxMonitoringAgent/#{OMS::Common.get_agent_version}"
        headers[OMS::CaseSensitiveString.new("x-ms-app")] = "LinuxMonitoringAgent"
        headers[OMS::CaseSensitiveString.new("x-ms-client-version")] = OMS::Common.get_agent_version
        headers[OMS::CaseSensitiveString.new("x-ms-client-platform")] = "Linux"

        req = Net::HTTP::Post.new(path, headers)
        json_msg = serializer.call(record)
        if json_msg.nil?
          return nil
        else
          if compress == true
            req.body = Zlib::Deflate.deflate(json_msg)
          else
            req.body = json_msg
          end
        end
        return req
      end # create_ods_request

      # parses the json record with appropriate encoding
      # parameters:
      #   record: Hash. body of the request
      # returns:
      #   json represention of object, 
      # nil if encoding cannot be applied 
      def parse_json_record_encoding(record)
        msg = nil
        begin
          msg = Yajl.dump(record)
        rescue => error 
          # failed encoding, encode to utf-8, iso-8859-1 and try again
          begin
            OMS::Log.warn_once("Yajl.dump() failed due to encoding, will try iso-8859-1 for #{record}: #{error}")

            if !record["DataItems"].nil?
              record["DataItems"].each do |item|
                item["Message"] = item["Message"].encode('utf-8', 'iso-8859-1')
              end
            end
            msg = Yajl.dump(record)
          rescue => error
            # at this point we've given up up, we don't recognize
            # the encode, so return nil and log_warning for the 
            # record
            OMS::Log.warn_once("Skipping due to failed encoding for #{record}: #{error}")
          end
        end
        return msg
      end

      # dump the records into json string
      # assume the records is an array of single layer hash
      # return nil if we cannot dump it
      # parameters:
      #   records: hash[]. an array of single layer hash
      def safe_dump_simple_hash_array(records)
        msg = nil

        begin
          msg = Yajl.dump(records)
        rescue => error
          OMS::Log.warn_once("Unable to dump to JSON string. #{error}")
          begin
            # failed to dump, encode to utf-8, iso-8859-1 and try again
            # records is an array of hash
            records.each do | hash |
              # the value is a hash
              hash.each do | key, value |
                # the value should be of simple type
                # encode the string to utf-8
                if value.instance_of? String
                  hash[key] = value.encode('utf-8', 'iso-8859-1')
                end
              end
            end

            msg = Yajl.dump(records)
          rescue => error
            # at this point we've given up, we don't recognize the encode,
            # so return nil and log_warning for the record
            OMS::Log.warn_once("Skipping due to failed encoding for #{records}: #{error}")
          end
        end

        return msg
      end # safe_dump_simple_hash_array

      # start a request
      # parameters:
      #   req: HTTPRequest. request
      #   secure_http: HTTP. HTTPS
      #   ignore404: bool. ignore the 404 error when it's true
      #   return_entire_response: bool. If true, return the entire response object
      # returns:
      #   string. body of the response (or the whole response if return_entire_response is true)
      def start_request(req, secure_http, ignore404 = false, return_entire_response = false)
        # Tries to send the passed in request
        # Raises an exception if the request fails.
        # This exception should only be caught by the fluentd engine so that it retries sending this 
        begin
          res = nil
          res = secure_http.start { |http|  http.request(req) }
        rescue => e # rescue all StandardErrors
          # Server didn't respond
          raise RetryRequestException, "Net::HTTP.#{req.method.capitalize} raises exception: #{e.class}, '#{e.message}'"
        else
          if res.nil?
            raise RetryRequestException, "Failed to #{req.method} at #{req.to_s} (res=nil)"
          end

          if res.is_a?(Net::HTTPSuccess)
            if return_entire_response
              return res
            else
              return res.body
            end
          end

          if ignore404 and res.code == "404"
            return ''
          end

          if res.code != "200"
            # Retry all failure error codes...
            res_summary = "(request-id=#{req["X-Request-ID"]}; class=#{res.class.name}; code=#{res.code}; message=#{res.message}; body=#{res.body};)"
            OMS::Log.error_once("HTTP Error: #{res_summary}")
            raise RetryRequestException, "HTTP error: #{res_summary}"
          end

        end # end begin
      end # end start_request
    end # Class methods

  end # class Common

  class IPcache
    
    def initialize(refresh_interval_seconds)
      @cache = {}
      @cache_lock = Mutex.new
      @refresh_interval_seconds = refresh_interval_seconds
      @condition = ConditionVariable.new
      @thread = Thread.new(&method(:refresh_cache))
    end

    def get_ip(hostname)
      if @cache.has_key?(hostname)
        return @cache[hostname]
      else
        ip = get_ip_from_socket(hostname)
        @cache_lock.synchronize {
          @cache[hostname] = ip
        }
        return ip
      end
    end

    private
    
    def get_ip_from_socket(hostname)
      begin
        Resolv::DNS.open do |dns|
          dns.timeouts = 3
          ip = dns.getaddress(hostname)
          return ip.to_s
       end
      rescue => error
        OMS::Log.error_once("Unable to resolve the IP of '#{hostname}': #{error}")
        return nil
      end
    end

    def refresh_cache
      while true
        @cache_lock.synchronize {
          @condition.wait(@cache_lock, @refresh_interval_seconds)
          # Flush the cache completely to prevent it from growing indefinitly
          @cache = {}
        }
      end
    end

  end

  class CaseSensitiveString < String
    def downcase
        self
    end
    def capitalize
        self
    end
    def to_s
        self
    end
  end


  require 'singleton'
  class BackgroundJobs
    include Singleton
    UNKOWN = "UNKOWN"
    LOG_ERROR = "LOG_ERROR"

    attr_reader :proc_cache
    def initialize
      @proc_cache = {}
      @proc_cache_lock = Mutex.new
      @master_process = Process.pid
      @log = $log

      ObjectSpace.define_finalizer(self, self.class.method(:finalize).to_proc)
    end

    private

    def get_log_tag()
      tag = "CHILD"
      tag = "PARENT" if @master_process == Process.pid
      return tag
    end

    def log(msg)
      @log.info "#{self.class.name}:#{get_log_tag} #{msg}"
    end

    def debug(msg)
      @log.debug "#{self.class.name}:#{get_log_tag} #{msg}"
    end

    def trace(msg)
      @log.trace "#{self.class.name}:#{get_log_tag} #{msg}"
    end

    def error(msg)
      @log.error "#{self.class.name}:#{get_log_tag} #{msg}"
    end

    def add_process_to_cache(pid)
      @proc_cache_lock.synchronize {
        @proc_cache[pid] = pid
      }
    end

    def remove_process_from_cache(pid)
      @proc_cache_lock.synchronize {
        @proc_cache.delete(pid)
      }
    end

    # This prevent more page faults from happening after the fork
    def run_garbage_collection()
      begin
        h = {}
        # Run GC 4 times to force garbage collection of short lived objects before doing the fork
        4.times { # maximum 4 times
          GC.stat(h)
          live_slots = h[:heap_live_slots] || h[:heap_live_slot]
          old_objects = h[:old_objects] || h[:old_object]
          remwb_unprotects = h[:remembered_wb_unprotected_objects] || h[:remembered_shady_object]
          young_objects = live_slots - old_objects - remwb_unprotects

          break if young_objects < live_slots / 10

          disabled = GC.enable
          GC.start(full_mark: false)
          GC.disable if disabled
        }
      rescue => e
        error(e.inspect)
      end
      # TODO: Run GC compaction here if possible
      # use this feature once is available, wait until ruby 2.7
      # GC.compact
    end

    public

    def self.finalize(object_id)
      return if Process.ppid == 1 or Process.pid != self.instance.get_mpid
      self.instance.cleanup
    end

    def get_mpid
      return @master_process
    end

    def cleanup
      return if @proc_cache.empty?
      log "Cleanup jobs, pid=#{Process.pid} mpid=#{self.get_mpid} ppid=#{Process.ppid}"

      @proc_cache.each do |pid, val|
        Process.kill('SIGTERM', pid)
      end

      @proc_cache.each do |pid, val|
        Process.kill('SIGKILL', pid)
      end
      @proc_cache_lock.synchronize {
        @proc_cache.clear
      }
    end

    def run_job_and_wait(&block)
      read_io, write_io = IO.pipe

      run_garbage_collection

      pid = fork do
        ["SIGHUP", "SIGTERM"].each do |sig|
          Signal.trap(sig) { log "Child process ##{Process.pid} receiving #{sig}\n"; exit }
        end

        read_io.close # For parent's use, not child's use
        result = {}
        begin
          yield_ret = yield
          trace "yield_ret=#{yield_ret}"

          yield_telemetry = []
          if yield_ret.is_a?(Array)
            yield_ret.each { |data|
              operation, source, event = UNKOWN, UNKOWN, nil
              event = data[:event] if data.is_a?(Hash) && data.key?(:event)
              # event = event[0] if event.is_a?(Array)
              source = data[:source] if data.is_a?(Hash) && data.key?(:source)
              if event.is_a?(String)
                operation = "LOG_ERROR"
              elsif event.is_a?(Hash) && event.key?(:op)
                operation = event[:op]
              end

              if event != nil and source != UNKOWN
                yield_telemetry.push({'operation': operation, 'event': event, 'source': source})
              end
            }
          end
          result[:telemetry] = yield_telemetry
          result[:return] = yield_ret
        rescue => e # We should catch any exception to pass it to parent
          result[:exception] = {'class': e.class.name, 'msg': e.message, 'backtrace': e.backtrace}
        end
        # process is orphan
        Process.exit(false) if Process.ppid == 1

        trace "write_io <= #{result}"
        write_io.write(result)
      end

      add_process_to_cache(pid)
      write_io.close # For child use
      # blocking read on pipe
      read = read_io.read
      results = eval(read)
      trace "Receiving read=#{read} results=#{results}"

      read_io.close
      Process.waitpid(pid)
      remove_process_from_cache(pid)

      unless results.is_a?(Hash)
        log "results is not a hash, results=#{results}"
        return results
      end

      # Handling Exception
      if results.key?(:exception) and results[:exception] != nil
        ex_class_name = results[:exception][:class]
        ex_msg = results[:exception][:msg]
        ex_backtrace = results[:exception][:backtrace]
        if Object.const_defined?(ex_class_name)
          ex = Object.const_get(ex_class_name, Class.new).new(ex_msg)
          ex.set_backtrace(ex_backtrace)
          raise ex
        else
          error "exception not found '#{ex_class_name}', we will raise a generic exception with msg='#{ex_msg}'"
          ex = StandardError.new(ex_msg)
          ex.set_backtrace(ex_backtrace)
          raise ex
        end
      end

      # Handling Telemetry
      if results.key?(:telemetry) and results[:telemetry] != nil
        results[:telemetry].each do |item|
          operation, event, source = item[:operation], item[:event], item[:source]
          debug "Handling operation=#{operation}, source=#{source}, event=#{event}"
          if operation === LOG_ERROR
            @log.error(event)
          else
            OMS::Telemetry.push_back_qos_event(source, event)
          end
        end
      end

      # Handling simple return
      if results.key?(:return) and results[:return] != nil
        return results[:return]
      end

      return nil
    end

    def run_job_async(callback, &block)
      thread = Thread.new {
        results = self.run_job_and_wait(&block)
        callback.call(results) if callback != nil
      }
    end

  end # BackgroundJobs

end # module OMS
