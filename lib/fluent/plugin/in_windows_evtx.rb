# frozen_string_literal: true

#
# Copyright 2019- Dan Sedlacek
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'helix_runtime'
require 'fluent-plugin-windows-evtx/native'
require 'fluent/plugin/input'
require 'fluent/plugin'

module Fluent::Plugin
  # A simple class that can read Windows EVTX files.
  class WindowsEvtxInput < Fluent::Plugin::Input
    Fluent::Plugin.register_input('windows_evtx', self)

    helpers :timer, :storage

    DEFAULT_STORAGE_TYPE = 'local'

    config_param :file_path, :string
    config_param :tag, :string
    config_param :read_interval, :time, default: 2

    config_section :storage do
      config_set_default :usage, 'positions'
      config_set_default :@type, DEFAULT_STORAGE_TYPE
      config_set_default :persistent, true
    end

    def configure(conf)
      super
      if @file_path.empty?
        raise Fluent::ConfigError,
              "windows_evtx: 'file' parameter is required on windows_evtx input"
      end

      @tag = tag
      @stop = false
      @pos_storage = storage_create(usage: 'positions')
    end

    def start
      super
      _start, _num = @pos_storage.get(@file_path)
      @evtx_log = EvtxLoader.new(@file_path)
      timer_execute("in_windows_evtx_#{@file_path}".to_sym, @read_interval) do
        on_notify(@file_path)
      end
    end

    def on_notify(_wut)
      # return unless @evtx_log.was_modified

      current_oldest_record_number = @evtx_log.oldest_record_number
      current_total_records = @evtx_log.total_records
      read_start, read_num = @pos_storage.get(@file_path)

      if read_start.zero? && read_num.zero?
        @pos_storage.put(
          @file_path,
          [current_oldest_record_number, current_total_records]
        )
        return
      end

      current_end = current_oldest_record_number + current_total_records - 1
      old_end = read_start + read_num - 1

      if current_oldest_record_number < read_start
        # may be a record number rotated.
        current_end += 0xFFFFFFFF
      end

      if current_end < old_end
        # something occured.
        @pos_storage.put(
          @file_path,
          [current_oldest_record_number, current_total_records]
        )
        return
      end

      @evtx_log.events.each do |event|
        router.emit(@tag, Fluent::Engine.now, event)
      end

      @pos_storage.put(@file_path, [read_start, read_num + events.length])
    end
  end
end
