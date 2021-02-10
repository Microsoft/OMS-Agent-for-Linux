# Copyright (c) Microsoft Corporation. All rights reserved.
require 'test/unit'
require_relative '../../../source/code/plugins/operation_lib'

class OperationTestRuntimeError < OperationModule::LoggingBase
  def log_error(text)
    raise text
  end
end

class OperationLib_Test < Test::Unit::TestCase
  class << self
    def startup
      @@operation_lib = OperationModule::Operation.new(OperationTestRuntimeError.new)
    end

    def shutdown
      #no op
    end
  end

  def test_filter_null_empty
    assert_equal({}, call_filter(nil), "null record fails")
    assert_equal({}, call_filter(""), "empty string record fails")
    assert_equal({}, call_filter(10), "int record fails")
    assert_equal({}, call_filter({}), "empty hash record fails")
  end

  def test_filter_invalid_hash
    assert_equal({}, call_filter({"name"=>"value"}), "invalid operation record - no type - fails")
    assert_equal({}, call_filter({"type"=>"oms"}), "invalid operation record - invalid type - fails")
    assert_equal({}, call_filter({"type"=>"out_oms"}), "invalid operation record - no config - fails")
    assert_equal({}, call_filter({"type"=>"out_oms", "config"=>"10"}), "invalid operation record - config not hash - fails")
    assert_equal({}, call_filter({"type"=>"out_oms", "config"=>{}}), "invalid operation record - config empty hash - fails")
    assert_equal({}, call_filter({"type"=>"out_oms", "config"=>{"buffer_queue_limit"=>10}}), "invalid operation record - config bufqlim not str - fails")
    assert_equal({}, call_filter({"type"=>"out_oms", "config"=>{"buffer_queue_limit"=>"10"}}), "invalid operation record - no bufqlen - fails")
    assert_equal({}, call_filter({"type"=>"out_oms", "config"=>{"buffer_queue_limit"=>"10"}, "buffer_queue_length"=>"10"}), "invalid operation record - bufqlen string - fails")
    assert_equal({}, call_filter({"type"=>"out_oms", "config"=>{"buffer_queue_limit"=>"str"}, "buffer_queue_length"=>10}), "invalid operation record - bufqlim not really int - fails")
  end 

  def test_filter_valid_hash
    assert_equal({}, call_filter({"type"=>"out_oms", "config"=>{"buffer_queue_limit"=>"10"}, "buffer_queue_length"=>8}), "valid record - bufq below limit - fails")
    data_item = call_filter({"type"=>"out_oms", "config"=>{"buffer_queue_limit"=>"10"}, "buffer_queue_length"=>9})
    assert(data_item.has_key?("Timestamp") && data_item.has_key?("OperationStatus") && data_item.has_key?("Computer") && data_item.has_key?("Detail") && data_item.has_key?("Category") && data_item.has_key?("Solution") && data_item.has_key?("HelpLink"))
  end

  def test_generic_filter
    assert_equal({}, call_generic_filter(nil), "null record fails")
    assert_equal({}, call_generic_filter(""), "empty string record fails")
    assert_equal({}, call_generic_filter(10), "int record fails")
    assert_equal({}, call_generic_filter({}), "empty hash record fails")

    data_item = call_generic_filter({"message"=>"This is a test message"})
    assert(data_item.has_key?("Computer") && data_item.has_key?("Timestamp") && data_item.has_key?("Detail") && data_item.has_key?("OperationStatus") && data_item.has_key?("Category") && data_item.has_key?("Solution"))
    assert_equal("This is a test message", data_item["Detail"])
  end
  # wrapper to call filter
  def call_filter(record)
    @@operation_lib.filter(record, Time.now)
  end

  def call_generic_filter(record)
    wrapper_record = @@operation_lib.filter_generic(record, Time.now)
  end

    # Note:  I haven't been able to find a helpful sounding name for any of the the
    # primary data record passed to these methods, nor what is labeled the DataItems
    # record which envelopes the former, nor the "wrapper", which envelopes the DataItems.
    # For now I will therefore call them as such:
    #   1.  Primary Data Record
    #   2.  Data Items Record
    #   3.  Wrapper Record
    # Given all these have the aspect of minimalist incremental additions rather
    # than designed patterns, a recommendation should be outstanding for consolidating
    # the patterns to classes or the equivalent across both omsagent and dsc, IMHO.  XC

  TestPrimaryRecords = [
    { :Pass => false,   :Type => :Bad,            :Evoke => false,  :Record => nil },
    { :Pass => false,   :Type => :Bad,            :Evoke => false,  :Record => "" },
    { :Pass => false,   :Type => :Bad,            :Evoke => false,  :Record => 10 },
    { :Pass => false,   :Type => :Bad,            :Evoke => false,  :Record => {} },
    { :Pass => true,    :Type => 'health',        :Evoke => false,  :Record => {"type"=>"out_oms", "config"=>{"buffer_queue_limit"=>"10"}, "buffer_queue_length"=>8} },
    { :Pass => true,    :Type => 'health',        :Evoke => true,   :Record => {"type"=>"out_oms", "config"=>{"buffer_queue_limit"=>"10"}, "buffer_queue_length"=>9} },
    { :Pass => true,    :Type => 'dsc',           :Evoke => true,   :Record => {"message"=>"Now is the time that all good engineers fully test their code."} },
    { :Pass => true,    :Type => 'dsc',           :Evoke => false,  :Record => {"other stuff"=>"any data"} },
    { :Pass => true,    :Type => 'auditd_plugin', :Evoke => true,   :Record => {"message"=>"Now is the time that all good engineers fully test their code."} },
    { :Pass => true,    :Type => 'auditd_plugin', :Evoke => false,  :Record => {"other stuff"=>"any data"} }
    ]

  def test_filter_and_wrap_tag_undefined
    [nil,"",{},"a","healthy","dy/dx"].each do |bad_tag|
      TestPrimaryRecords.each do |tr|
        assert_equal({}, @@operation_lib.filter_and_wrap(bad_tag,tr[:Record],Time.now),"All calls with invalid tags should return an empty hash.")
      end
    end
  end

  def test_filter_and_wrap
    TestPrimaryRecords.each do |tr|
      wrapper_record = @@operation_lib.filter_and_wrap(tr[:Type],tr[:Record],Time.now)

      if tr[:Type] == :Bad
        assert_equal({}, wrapper_record,"Should be empty.")
      else
        if tr[:Evoke] then

          # All records validation:
          # Top Wrappings:
          assert_not_equal({}, wrapper_record,"Should NOT be empty.")

          assert_equal("OPERATION_BLOB",wrapper_record['DataType'],"Should be of DataType 'OPERATION_BLOB'.")
          assert_equal("LogManagement",wrapper_record['IPName'],"Should be of IPName 'LogManagement'.")
          assert_equal(1,wrapper_record['DataItems'].length,"Should have one record.")
          assert_equal(Hash,wrapper_record['DataItems'][0].class,"Should have record of type Hash.")

          dataitem_record = wrapper_record['DataItems'][0] 

          assert(dataitem_record.has_key?('Computer'),"Should have a Computer key.")
          assert_equal(dataitem_record['Computer'].class,String,"Computer should be a ruby String.")
          assert(dataitem_record.has_key?('Timestamp'),"Should have a Timestamp key.")
          assert_false(dataitem_record['Timestamp'].nil?,"Should have a Timestamp object of type .")
          assert(dataitem_record.has_key?('Detail'),"Should have a Detail key.")
          assert_equal(dataitem_record['Detail'].class,String,"Detail should be a ruby String.")
          assert(dataitem_record.has_key?('OperationStatus'),"Should have a OperationStatus key.")
          assert_equal(dataitem_record['OperationStatus'].class,String,"OperationStatus should be a ruby String.")
          assert(dataitem_record.has_key?('Category'),"Should have a Category key.")
          assert_equal(dataitem_record['Category'].class,String,"Category should be a ruby String.")
          assert(dataitem_record.has_key?('Solution'),"Should have a Solution key.")
          assert_equal(dataitem_record['Solution'].class,String,"Solution should be a ruby String.")

          # Note about HelpLink, which is empty:
          #  Should this be ignored for now, refactored to be useful, or removed?
          case tr[:Type]
            when 'buffer'
                assert(dataitem_record.has_key?('HelpLink'),"Should have a HelpLink key.")
            when 'health'
                assert(dataitem_record.has_key?('HelpLink'),"Should have a HelpLink key.")
          end
        else
          # Not :Evoke(d) case where no data of importance needed be conveyed:
          assert_equal({}, wrapper_record,"Should be empty.")
        end
      end
    end
  end

end
