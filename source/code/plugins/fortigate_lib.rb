require_relative 'oms_common'

module Fortinet
    class Fortigate

      def initialize(log)
          @log = log
      end

      def parse(record)
        #mock message
        # 11:03 devname=BEN99 devid=FG300C3912609999 logid=1059028705 type=utm subtype=app-ctrl 
        # eventtype=app-ctrl-all level=warning vd="root" appid=28046 user="" srcip=192.168.17.138 srcport=55229 srcintf="port8" 
        # dstip=52.94.219.66 dstport=443 dstintf="port1" proto=6 service="HTTPS" policyid=199 sessionid=62501726 applist="XXXX IT" appcat="Video/Audio" 
        # app="Amazon.Video" action=block hostname="atv-ps-eu.amazon.com" url="/" msg="Video/Audio: Amazon.Video," apprisk=elevated

        #now process and transform message in a CEF compatible format
        #to parse the tokens easily we need to replace spaces between "" with a non printable char
        #use string split to have the label=value patterns
        #iterate the patterns and translate the key
        #reassemble the string CEF like

        @log.debug "Fortigate raw message: " + record['message']

        keyword_map = {
          "devname" => "dvchost",
          "devid" => "deviceExternalId",
          "logid" => nil,
          "type" => "cs1",
          "subtype" => "cs2",
          "eventtype" => "cs3",
          "level" => "cat",
          "vd" => "suser",
          "appid" => nil,
          "user" => "duser",
          "srcip" => "src",
          "srcport" => "spt",
          "srcintf" => nil,
          "dstip" => "dst",
          "dstport" => "dpt",
          "dstintf" => nil,
          "proto" => nil,
          "service" => "app",
          "policyid" => nil,
          "applist" => nil,
          "appcat" => "cs4",
          "app" => nil,
          "action" => "act",
          "hostname" => "dhost",
          "url" => "request",
          "msg" => "msg",
          "apprisk" => nil
        }

        header_map = {
          "devid" => "deviceProduct",
          "policyid" => "signatureId",
          "level" => "severity",
          "action" => "action",
          "applist" => "applist"
        }
        #intermediate char used to facilitate parsing
        rep_char='_'
        escaping_rules = {
          "=" => "\\=",
          "\\" => "\\\\",
          "\"" => "",
          rep_char => " "
        }

        #build an error message to use when something goes really wrong
        raw_message=record['message'].clone
        escaping_rules.each do |k,v|
          raw_message.gsub!(k,v)
        end
        raw_message="CEF:0|Fortinet|unknown|n.a.|-1|Unknown format|error|msg=#{raw_message}"
      

        #must have properties, if not post the entry anyway without any parsing
        #unless record['message'].match(/devid=(?:.*)level=(?:.*)policyid=(?:.*)action=/) then
        unless record['message'].match(/devid=(?:.*)level=(?:.*)action=/) then
          @log.warn "Unknown Fortigate message format: " + record['message']
          record['Message'] = raw_message
          record.delete 'message'
          return record
        end

        #didn't find a way using regexp, so let's do some brute force and see if we any impact on cpu
        #logic
        # take all the strings between "" and replace any space with rep_char
        # reassemble the string
        # split using space as a delimiter to get label=value tokens
        # iterate to generate an hash and escaping any needed char

        #let's implement a ctach all here
        begin
          tokens=record['message'].split('"')
          for i in 0..tokens.length-1
            if i.odd?
              tokens[i].gsub!(/\s/,rep_char)
            end
          end
          tokens=tokens.join('"').split(' ')
          #first token in fortigate log is useless, delete it
          tokens.delete_at(0)

          result={}
          prefix={}
          tokens.each do |t|
            parts=t.split('=')
            if keyword_map.has_key?(parts[0])
              unless keyword_map[parts[0]].nil? 
                value = parts[1]
                escaping_rules.each do |k,v|
                  value.gsub!(k,v)
                end
                result[keyword_map[parts[0]]]=value
              end
            end
            if header_map.has_key?(parts[0])
              unless header_map[parts[0]].nil? 
                value = parts[1]
                escaping_rules.each do |k,v|
                  value.gsub!(k,v)
                end
                prefix[header_map[parts[0]]]=value
              end
            end        
          end

          #for standard sake add the labels for the custom fields but they're not used in Log Analytics
          result['cs1label']='type'
          result['cs2label']='subtype'
          result['cs3label']='eventtype'
          result['cs4label']='appcat'

          #now build the message
          extension=''
          result.each do |k,v|
            extension="#{extension} #{k}=#{v}"
          end

          #just in case we report the full original message in cs5
          extension="#{extension} cs5=#{raw_message}"

          name=if prefix.has_key?('applist') then prefix['applist'] else 'unknown' end
          name+=' ' + if prefix.has_key?('action') then prefix['action'] else 'unknown' end

          deviceProduct=if prefix.has_key?('deviceProduct') then prefix['deviceProduct'] else 'unknown' end
          signatureId=if prefix.has_key?('signatureId') then prefix['signatureId'] else 'unknown' end
          severity=if prefix.has_key?('severity') then prefix['severity'] else 'unknown' end
          message="CEF:0|Fortinet|#{deviceProduct}|n.a.|#{signatureId}|#{name}|#{severity}|#{extension}"

          record['Message'] = message
          record.delete 'message'

          return record
        rescue
          @log.error "Error parsing fortigate log entry" + record['message']
          record['Message'] = raw_message
          record.delete 'message'
          return record
        end
      end
    end # class
end # module