require 'test/unit'
require_relative 'omstestlib'
require_relative ENV['BASE_DIR'] + '/source/code/plugins/fortigate_lib'

class FortigateLibTest < Test::Unit::TestCase
    class << self
        def startup
        @@fortigate_plugin = Fortinet::Fortigate.new(OMS::MockLog.new)
        end

        def shutdown
        #no op
        end
    end
       
    def test_record_parsing
        record = {
          'message' => '11:03 devname=BEN99 devid=FG300C3912609999 logid=1059028705 type=utm subtype=app-ctrl eventtype=app-ctrl-all level=warning vd="root" appid=28046 user="" srcip=192.168.17.138 srcport=55229 srcintf="port8" dstip=52.94.219.66 dstport=443 dstintf="port1" proto=6 service="HTTPS" policyid=199 sessionid=62501726 applist="XXXX IT" appcat="Video/ Audio" app="Amazon.Video" action=block hostname="atv-ps-eu.amazon.com" url="/" msg="Video/Audio: Amazon.Video," apprisk=elevated'
        }
                
        expected_message='CEF:0|Fortinet|FG300C3912609999|n.a.|199|XXXX IT block|warning| dvchost=BEN99 deviceExternalId=FG300C3912609999 cs1=utm cs2=app-ctrl cs3=app-ctrl-all cat=warning suser=root duser= src=192.168.17.138 spt=55229 dst=52.94.219.66 dpt=443 app=HTTPS cs4=Video/ Audio act=block dhost=atv-ps-eu.amazon.com request=/ msg=Video/Audio: Amazon.Video, cs1label=type cs2label=subtype cs3label=eventtype cs4label=appcat cs5=CEF:0|Fortinet|unknown|n.a.|-1|Unknown format|error|msg=11:03 devname\=BEN99 devid\=FG300C3912609999 logid\=1059028705 type\=utm subtype\=app-ctrl eventtype\=app-ctrl-all level\=warning vd\=root appid\=28046 user\= srcip\=192.168.17.138 srcport\=55229 srcintf\=port8 dstip\=52.94.219.66 dstport\=443 dstintf\=port1 proto\=6 service\=HTTPS policyid\=199 sessionid\=62501726 applist\=XXXX IT appcat\=Video/ Audio app\=Amazon.Video action\=block hostname\=atv-ps-eu.amazon.com url\=/ msg\=Video/Audio: Amazon.Video, apprisk\=elevated'
        
        record = @@fortigate_plugin.parse(record)
        assert_equal(expected_message, record['Message'], 'invalid record format') 
    end

    def test_unknownrecord_parsing
      record = {
        'message' => '11:03 devname=BEN99 logid=1059028705 type=utm subtype=app-ctrl eventtype=app-ctrl-all level=warning vd="root" appid=28046 dstip=52.94.219.66 dstport=443'
      }

      expected_message='CEF:0|Fortinet|unknown|n.a.|-1|Unknown format|error|msg=11:03 devname\=BEN99 logid\=1059028705 type\=utm subtype\=app-ctrl eventtype\=app-ctrl-all level\=warning vd\=root appid\=28046 dstip\=52.94.219.66 dstport\=443'
      
      record = @@fortigate_plugin.parse(record)
      assert_equal(expected_message, record['Message'], 'invalid record format')        
  end

end
