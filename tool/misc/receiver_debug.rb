#!/usr/bin/ruby
# coding: cp932

=begin
Debug GPS receiver with Ruby via SWIG interface
=end

[
  File::join(File::dirname(__FILE__), '..', 'swig', 'build_SWIG'),
].each{|dir|
  $: << dir unless $:.include?(dir)
}
require 'GPS.so'

class GPS_Receiver

  GPS::Time.send(:define_method, :utc){ # send as work around of old Ruby
    res = c_tm(GPS::Time::guess_leap_seconds(self))
    res[-1] += (seconds % 1)
    res
  }

  def self.pvt_items(opt = {})
    opt = {
      :system => [[:GPS, 1..32]],
      :satellites => (1..32).to_a,
    }.merge(opt)
    [[
      [:week, :itow_rcv, :year, :month, :mday, :hour, :min, :sec_rcv_UTC],
      proc{|pvt|
        [:week, :seconds, :utc].collect{|f| pvt.receiver_time.send(f)}.flatten
      }
    ]] + [[
      [:receiver_clock_error_meter, :longitude, :latitude, :height, :rel_E, :rel_N, :rel_U],
      proc{|pvt|
        next [nil] * 7 unless pvt.position_solved?
        [
          pvt.receiver_error,
          pvt.llh.lng / Math::PI * 180,
          pvt.llh.lat / Math::PI * 180,
          pvt.llh.alt,
        ] + (pvt.rel_ENU.to_a rescue [nil] * 3)
      } 
    ]] + [proc{
      labels = [:g, :p, :h, :v, :t].collect{|k| "#{k}dop".to_sym}
      [
        labels,
        proc{|pvt|
          next [nil] * 5 unless pvt.position_solved?
          labels.collect{|k| pvt.send(k)}
        }
      ]
    }.call] + [[
      [:v_north, :v_east, :v_down, :receiver_clock_error_dot_ms],
      proc{|pvt|
        next [nil] * 4 unless pvt.velocity_solved?
        [:north, :east, :down].collect{|k| pvt.velocity.send(k)} \
            + [pvt.receiver_error_rate] 
      }
    ]] + [
      [:used_satellites, proc{|pvt| pvt.used_satellites}],
    ] + opt[:system].collect{|sys, range|
      range = range.kind_of?(Array) ? proc{
        # check whether inputs can be converted to Range
        next nil if range.empty?
        a, b = range.minmax
        ((b - a) == (range.length - 1)) ? (a..b) : range
      }.call : range
      next nil unless range
      bit_flip, label = case range
      when Array
        [proc{|res, i|
          res[i] = "1" if i = range.index(i)
          res
        }, range.collect{|pen| pen & 0xFF}.reverse.join('+')]
      when Range
        base_prn = range.min
        [proc{|res, i|
          res[i - base_prn] = "1" if range.include?(i)
          res
        }, [:max, :min].collect{|f| range.send(f) & 0xFF}.join('..')]
      end
      ["#{sys}_PRN(#{label})", proc{|pvt|
        pvt.used_satellite_list.inject("0" * range.size, &bit_flip) \
            .scan(/.{1,8}/).join('_').reverse
      }]
    }.compact + [[
      opt[:satellites].collect{|prn, label|
        [:range_residual, :weight, :azimuth, :elevation, :slopeH, :slopeV].collect{|str|
          "#{str}(#{label || prn})"
        }
      }.flatten,
      proc{|pvt|
        next ([nil] * 6 * opt[:satellites].size) unless pvt.position_solved?
        sats = pvt.used_satellite_list
        r, w = [:delta_r, :W].collect{|f| pvt.send(f)}
        opt[:satellites].collect{|prn, label|
          next ([nil] * 6) unless i2 = sats.index(prn)
          [r[i2, 0], w[i2, i2]] +
              [:azimuth, :elevation].collect{|f|
                pvt.send(f)[prn] / Math::PI * 180
              } + [pvt.slopeH[prn], pvt.slopeV[prn]]
        }.flatten
      },
    ]] + [[
      [:wssr, :wssr_sf, :weight_max,
          :slopeH_max, :slopeH_max_PRN, :slopeH_max_elevation,
          :slopeV_max, :slopeV_max_PRN, :slopeV_max_elevation],
      proc{|pvt|
        next [nil] * 9 unless fd = pvt.fd
        el_deg = [4, 6].collect{|i| pvt.elevation[fd[i]] / Math::PI * 180}
        fd[0..4] + [el_deg[0]] + fd[5..6] + [el_deg[1]]
      }
    ]] + [[
      [:wssr_FDE_min, :wssr_FDE_min_PRN, :wssr_FDE_2nd, :wssr_FDE_2nd_PRN],
      proc{|pvt|
        [:fde_min, :fde_2nd].collect{|f|
          info = pvt.send(f)
          next ([nil] * 2) if (!info) || info.empty?
          [info[0], info[-3]] 
        }.flatten
      }
    ]]
  end

  def self.meas_items(opt = {})
    opt = {
      :satellites => (1..32).to_a,
    }.merge(opt)
    keys = [:PSEUDORANGE, :RANGE_RATE, :DOPPLER, :FREQUENCY].collect{|k|
      GPS::Measurement.const_get("L1_#{k}".to_sym)
    }
    [[
      opt[:satellites].collect{|prn, label|
        [:L1_range, :L1_rate].collect{|str| "#{str}(#{label || prn})"}
      }.flatten,
      proc{|meas|
        meas_hash = meas.to_hash
        opt[:satellites].collect{|prn, label|
          pr, rate, doppler, freq = keys.collect{|k| meas_hash[prn][k] rescue nil}
          freq ||= GPS::SpaceNode.L1_Frequency
          [pr, rate || ((doppler * GPS::SpaceNode::light_speed / freq) rescue nil)]
        }
      }
    ]]
  end

  def header
    (@output[:pvt] + @output[:meas]).transpose[0].flatten.join(',')
  end
    
  attr_accessor :solver
  attr_accessor :base_station

  def initialize(options = {})
    @solver = GPS::Solver::new
    @solver.hooks[:relative_property] = proc{|prn, rel_prop, meas, rcv_e, t_arv, usr_pos, usr_vel|
      rel_prop[0] = 1 if rel_prop[0] > 0 # weight = 1
      rel_prop
    }
    @debug = {}
    solver_opts = [:gps_options].collect{|target|
      @solver.send(target)
    }
    solver_opts.each{|opt|
      # default solver options
      opt.elevation_mask = 0.0 / 180 * Math::PI # 0 deg (use satellite over horizon)
      opt.residual_mask = 1E4 # 10 km (without residual filter, practically)
    }
    output_options = {
      :system => [[:GPS, 1..32]],
      :satellites => (1..32).to_a, # [idx, ...] or [[idx, label], ...] is acceptable
    }
    options = options.reject{|k, v|
      case k
      when :debug
        v = v.split(/,/)
        @debug[v[0].upcase.to_sym] = v[1..-1]
        next true
      when :weight
        case v.to_sym
        when :elevation # (same as underneath C++ library)
          @solver.hooks[:relative_property] = proc{|prn, rel_prop, meas, rcv_e, t_arv, usr_pos, usr_vel|
            if rel_prop[0] > 0 then
              elv = Coordinate::ENU::relative_rel(
                  Coordinate::XYZ::new(*rel_prop[4..6]), usr_pos).elevation
              rel_prop[0] = (Math::sin(elv)/0.8)**2
            end
            rel_prop
          }
          next true
        when :identical # same as default
          next true
        end
      when :elevation_mask_deg
        raise "Unknown elevation mask angle: #{v}" unless elv_deg = (Float(v) rescue nil)
        $stderr.puts "Elevation mask: #{elv_deg} deg"
        solver_opts.each{|opt|
          opt.elevation_mask = elv_deg / 180 * Math::PI # 0 deg (use satellite over horizon)
        }
        next true
      when :base_station
        crd, sys = v.split(/ *, */).collect.with_index{|item, i|
          case item
          when /^([\+-]?\d+\.?\d*)([XYZNEDU]?)$/ # ex) meter[X], degree[N]
            [$1.to_f, ($2 + "XY?"[i])[0]]
          when /^([\+-]?\d+)_(?:(\d+)_(\d+\.?\d*)|(\d+\.?\d*))([NE])$/ # ex) deg_min_secN
            [$1.to_f + ($2 || $4).to_f / 60 + ($3 || 0).to_f / 3600, $5]
          else
            raise "Unknown coordinate spec.: #{item}"
          end
        }.transpose
        raise "Unknown base station: #{v}" if crd.size != 3
        @base_station = case (sys = sys.join.to_sym)
        when :XYZ, :XY?
          Coordinate::XYZ::new(*crd)
        when :NED, :ENU, :NE?, :EN? # :NE? => :NEU, :EN? => :ENU
          (0..1).each{|i| crd[i] *= (Math::PI / 180)}
          ([:NED, :NE?].include?(sys) ?
              Coordinate::LLH::new(crd[0], crd[1], crd[2] * (:NED == sys ? -1 : 1)) :
              Coordinate::LLH::new(crd[1], crd[0], crd[2])).xyz
        else
          raise "Unknown coordinate system: #{sys}"
        end
        $stderr.puts "Base station (LLH): #{
          llh = @base_station.llh.to_a
          llh[0..1].collect{|rad| rad / Math::PI * 180} + [llh[2]]
        }"
        next true
      when :with, :without
        [v].flatten.each{|spec| # array is acceptable
          sys, svid = case spec
          when Integer
            [nil, spec]
          when /^([a-zA-Z]+)(?::(-?\d+))?$/
            [$1.upcase.to_sym, (Integer($2) rescue nil)]
          when /^-?\d+$/
            [nil, $&.to_i]
          else
            next false
          end
          mode = if svid && (svid < 0) then
            svid *= -1
            (k == :with) ? :exclude : :include
          else
            (k == :with) ? :include : :exclude
          end
          update_output = proc{|sys_target, prns, labels|
            unless (i = output_options[:system].index{|sys, range| sys == sys_target}) then
              i = -1
              output_options[:system] << [sys_target, []]
            else
              output_options[:system][i][1].reject!{|prn| prns.include?(prn)}
            end
            output_options[:satellites].reject!{|prn, label| prns.include?(prn)}
            if mode == :include then
              output_options[:system][i][1] += prns
              output_options[:system][i][1].sort!
              output_options[:satellites] += (labels ? prns.zip(labels) : prns)
              output_options[:satellites].sort!{|a, b| [a].flatten[0] <=> [b].flatten[0]}
            end
          }
          check_sys_svid = proc{|sys_target, range_in_sys, offset|
            next range_in_sys.include?(svid - (offset || 0)) unless sys # svid is specified without system
            next false unless sys == sys_target
            next true unless svid # All satellites in a target system (svid == nil)
            range_in_sys.include?(svid)
          }
          if check_sys_svid.call(:GPS, 1..32) then
            [svid || (1..32).to_a].flatten.each{|prn| @solver.gps_options.send(mode, prn)}
          else
            raise "Unknown satellite: #{spec}"
          end
          $stderr.puts "#{mode.capitalize} satellite: #{[sys, svid].compact.join(':')}"
        }
        next true
      end
      false
    }
    raise "Unknown receiver options: #{options.inspect}" unless options.empty?
    @output = {
      :pvt => GPS_Receiver::pvt_items(output_options),
      :meas => GPS_Receiver::meas_items(output_options),
    }
  end

  GPS::Measurement.class_eval{
    proc{
      key2sym = []
      GPS::Measurement.constants.each{|k|
        i = GPS::Measurement.const_get(k)
        key2sym[i] = k if i.kind_of?(Integer)
      }
      define_method(:to_a2){
        to_a.collect{|prn, k, v| [prn, key2sym[k] || k, v]}
      }
      define_method(:to_hash2){
        Hash[*(to_hash.collect{|prn, k_v|
          [prn, Hash[*(k_v.collect{|k, v| [key2sym[k] || k, v]}.flatten(1))]]
        }.flatten(1))]
      }
    }.call
    alias_method(:add_orig, :add)
    define_method(:add){|prn, key, value|
      add_orig(prn, key.kind_of?(Symbol) ? GPS::Measurement.const_get(key) : key, value)
    }
  }

  def run(meas, t_meas, ref_pos = @base_station)
=begin
    meas.to_a.collect{|prn, k, v| prn}.uniq.each{|prn|
      eph = @solver.gps_space_node.ephemeris(prn)
      $stderr.puts "XYZ(PRN:#{prn}): #{eph.constellation(t_meas)[0].to_a} (iodc: #{eph.iodc}, iode: #{eph.iode})"
    }
=end

    #@solver.gps_space_node.update_all_ephemeris(t_meas) # internally called in the following solver.solve
    pvt = @solver.solve(meas, t_meas)
    pvt.define_singleton_method(:rel_ENU){
      Coordinate::ENU::relative(xyz, ref_pos)
    } if (ref_pos && pvt.position_solved?)
    output = @output
    pvt.define_singleton_method(:to_s){
      (output[:pvt].transpose[1].collect{|task|
        task.call(pvt)
      } + output[:meas].transpose[1].collect{|task|
        task.call(meas)
      }).flatten.join(',')
    }
    pvt
  end

  GPS::PVT.class_eval{
    define_method(:post_solution){|target|
      sats, az, el = proc{|g|
        self.used_satellite_list.collect.with_index{|prn, i|
          # G_enu is measured in the direction from satellite to user positions
          [prn,
              Math::atan2(-g[i, 0], -g[i, 1]),
              Math::asin(-g[i, 2])]
        }.transpose
      }.call(self.G_enu) rescue [[], [], []]
      [[:@azimuth, az], [:@elevation, el]].each{|k, values|
        self.instance_variable_set(k, Hash[*(sats.zip(values).flatten(1))])
      }
      mat_S = self.S
      [:@slopeH, :@slopeV] \
          .zip((self.fd ? self.slope_HV_enu(mat_S).to_a.transpose : [nil, nil])) \
          .each{|k, values|
        self.instance_variable_set(k,
            Hash[*(values ? sats.zip(values).flatten(1) : [])])
      }
      # If a design matrix G has columns larger than 4, 
      # other states excluding position and time are estimated.
      @other_state = self.position_solved? \
          ? (mat_S * self.delta_r.partial(self.used_satellites, 1, 0, 0)).transpose.to_a[0][4..-1] \
          : []
      instance_variable_get(target)
    }
    [:azimuth, :elevation, :slopeH, :slopeV, :other_state].each{|k|
      eval("define_method(:#{k}){@#{k} || self.post_solution(:@#{k})}")
    }
  }
  
  proc{
    eph_list = Hash[*(1..32).collect{|prn|
      eph = GPS::Ephemeris::new
      eph.svid = prn
      [prn, eph]
    }.flatten(1)]
    define_method(:register_ephemeris){|t_meas, sys, prn, bcast_data|
      case sys
      when :GPS
        next unless eph = eph_list[prn]
        sn = @solver.gps_space_node
        subframe, iodc_or_iode = eph.parse(bcast_data)
        if iodc_or_iode < 0 then
          begin
            sn.update_iono_utc(
                GPS::Ionospheric_UTC_Parameters::parse(bcast_data))
            [:alpha, :beta].each{|k|
              $stderr.puts "Iono #{k}: #{sn.iono_utc.send(k)}"
            } if false
          rescue
          end
          next
        end
        if t_meas and eph.consistent? then
          eph.WN = ((t_meas.week / 1024).to_i * 1024) + (eph.WN % 1024)
          sn.register_ephemeris(prn, eph)
          eph.invalidate
        end
      end
    }
  }.call
  
  def parse_ubx(ubx_fname, &b)
    $stderr.print "Reading UBX file (%s) "%[ubx_fname]
    require_relative 'ubx'
  
    ubx = UBX::new(open(ubx_fname))  
    ubx_kind = Hash::new(0)
    
    after_run = b || proc{|pvt| puts pvt.to_s if pvt}
    
    gnss_serial = proc{|svid, sys|
      if sys then # new numbering
        sys = [:GPS, :SBAS, :Galileo, :BeiDou, :IMES, :QZSS, :GLONASS][sys] if sys.kind_of?(Integer)
        case sys
        when :QZSS; svid += 192
        end
      else # old numbering
        sys = case svid
        when 1..32; :GPS
        when 120..158; :SBAS
        when 193..202; :QZSS
        when 65..96; svid -= 64; :GLONASS
        when 255; :GLONASS
        end
      end
      [sys, svid]
    }
    
    t_meas = nil
    ubx.each_packet.with_index(1){|packet, i|
      $stderr.print '.' if i % 1000 == 0
      ubx_kind[packet[2..3]] += 1
      case packet[2..3]
      when [0x02, 0x10] # RXM-RAW
        msec, week = [[0, 4, "V"], [4, 2, "v"]].collect{|offset, len, str|
          packet.slice(6 + offset, len).pack("C*").unpack(str)[0]
        }
        t_meas = GPS::Time::new(week, msec.to_f / 1000)
        meas = GPS::Measurement::new
        packet[6 + 6].times{|i|
          loader = proc{|offset, len, str|
            ary = packet.slice(6 + offset + (i * 24), len)
            str ? ary.pack("C*").unpack(str)[0] : ary
          }
          prn = loader.call(28, 1)[0]
          {
            :L1_PSEUDORANGE => [16, 8, "E"],
            :L1_DOPPLER => [24, 4, "e"],
            :L1_CARRIER_PHASE => [8, 8, "E"],
            :L1_SIGNAL_STRENGTH_dBHz => [30, 1, "c"],
          }.each{|k, prop|
            meas.add(prn, k, loader.call(*prop))
          }
          # bit 0 of RINEX LLI (loss of lock indicator) shows lost lock
          # between previous and current observation, which maps negative lock seconds
          meas.add(prn, :L1_LOCK_SEC,
              (packet[6 + 31 + (i * 24)] & 0x01 == 0x01) ? -1 : 0)
        }
        after_run.call(run(meas, t_meas), [meas, t_meas])
      when [0x02, 0x15] # RXM-RAWX
        sec, week = [[0, 8, "E"], [8, 2, "v"]].collect{|offset, len, str|
          packet.slice(6 + offset, len).pack("C*").unpack(str)[0]
        }
        t_meas = GPS::Time::new(week, sec)
        meas = GPS::Measurement::new
        packet[6 + 11].times{|i|
          loader = proc{|offset, len, str, post|
            v = packet.slice(6 + offset + (i * 32), len)
            v = str ? v.pack("C*").unpack(str)[0] : v
            v = post.call(v) if post
            v
          }
          sys, svid = gnss_serial.call(*loader.call(36, 2).reverse)
          case sys
          when :GPS; 
          else; next
          end
          trk_stat = loader.call(46, 1)[0]
          {
            :L1_PSEUDORANGE => [16, 8, "E", proc{|v| (trk_stat & 0x1 == 0x1) ? v : nil}],
            :L1_PSEUDORANGE_SIGMA => [43, 1, nil, proc{|v|
              (trk_stat & 0x1 == 0x1) ? (1E-2 * (1 << (v[0] & 0xF))) : nil
            }],
            :L1_DOPPLER => [32, 4, "e"],
            :L1_DOPPLER_SIGMA => [45, 1, nil, proc{|v| 2E-3 * (1 << (v[0] & 0xF))}],
            :L1_CARRIER_PHASE => [24, 8, "E", proc{|v| (trk_stat & 0x2 == 0x2) ? v : nil}],
            :L1_CARRIER_PHASE_SIGMA => [44, 1, nil, proc{|v|
              (trk_stat & 0x2 == 0x2) ? (0.004 * (v[0] & 0xF)) : nil
            }],
            :L1_SIGNAL_STRENGTH_dBHz => [42, 1, "C"],
            :L1_LOCK_SEC => [40, 2, "v", proc{|v| 1E-3 * v}],
          }.each{|k, prop|
            next unless v = loader.call(*prop)
            meas.add(svid, k, v)
          }
        }
        after_run.call(run(meas, t_meas), [meas, t_meas])
      when [0x02, 0x11] # RXM-SFRB
        sys, svid = gnss_serial.call(packet[6 + 1])
        register_ephemeris(
            t_meas,
            sys, svid,
            packet.slice(6 + 2, 40).each_slice(4).collect{|v|
              res = v.pack("C*").unpack("V")[0]
              (sys == :GPS) ? ((res & 0xFFFFFF) << 6) : res
            })
      when [0x02, 0x13] # RXM-SFRBX
        sys, svid = gnss_serial.call(packet[6 + 1], packet[6])
        register_ephemeris(
            t_meas,
            sys, svid,
            packet.slice(6 + 8, 4 * packet[6 + 4]).each_slice(4).collect{|v|
              v.pack("C*").unpack("V")[0]
            })
      end
    }
    $stderr.puts ", found packets are %s"%[ubx_kind.inspect]
  end
  
  def parse_rinex_nav(fname)
    items = [
      @solver.gps_space_node,
    ].inject(0){|res, sn|
      loaded_items = sn.send(:read, fname)
      raise "Format error! (Not RINEX) #{fname}" if loaded_items < 0
      res + loaded_items
    }
    $stderr.puts "Read RINEX NAV file (%s): %d items."%[fname, items]
  end
  
  def parse_rinex_obs(fname, &b)
    after_run = b || proc{|pvt| puts pvt.to_s if pvt}
    $stderr.print "Reading RINEX observation file (%s)"%[fname]
    types = nil
    count = 0
    GPS::RINEX_Observation::read(fname){|item|
      $stderr.print '.' if (count += 1) % 1000 == 0
      t_meas = item[:time]

      types ||= Hash[*(item[:meas_types].collect{|sys, values|
        [sys, values.collect.with_index{|type_, i|
          case type_
          when "C1", "C1C"
            [i, :L1_PSEUDORANGE]
          when "L1", "L1C"
            [i, :L1_CARRIER_PHASE]
          when "D1", "D1C"
            [i, :L1_DOPPLER]
          when "S1", "S1C"
            [i, :L1_SIGNAL_STRENGTH_dBHz]
          else
            nil 
          end
        }.compact]
      }.flatten(1))]

      meas = GPS::Measurement::new
      item[:meas].each{|k, v|
        sys, prn = k
        case sys
        when 'G', ' '
        when 'J'; prn += 192
        else; next
        end
        types[sys] = (types[' '] || []) unless types[sys]
        types[sys].each{|i, type_|
          meas.add(prn, type_, v[i][0]) if v[i]
        }
      }
      after_run.call(run(meas, t_meas), [meas, t_meas])
    }
    $stderr.puts ", %d epochs."%[count] 
  end
  
  def attach_sp3(fname)
    @sp3 ||= GPS::SP3::new
    read_items = @sp3.read(fname)
    raise "Format error! (Not SP3) #{fname}" if read_items < 0
    $stderr.puts "Read SP3 file (%s): %d items."%[fname, read_items]
    sats = @sp3.satellites
    @sp3.class.constants.each{|sys|
      next unless /^SYS_(?!SYSTEMS)(.*)/ =~ sys.to_s
      idx, sys_name = [@sp3.class.const_get(sys), $1]
      next unless sats[idx] > 0
      next unless @sp3.push(@solver, idx)
      $stderr.puts "Change ephemeris source of #{sys_name} to SP3" 
    }
  end
  
  def attach_antex(fname)
    raise "Specify SP3 before ANTEX application!" unless @sp3
    applied_items = @sp3.apply_antex(fname)
    raise "Format error! (Not ANTEX) #{fname}" unless applied_items >= 0
    $stderr.puts "SP3 correction with ANTEX file (%s): %d items have been processed."%[fname, applied_items]
  end
  
  def attach_rinex_clk(fname)
    @clk ||= GPS::RINEX_Clock::new
    read_items = @clk.read(fname)
    raise "Format error! (Not RINEX clock) #{fname}" if read_items < 0
    $stderr.puts "Read RINEX clock file (%s): %d items."%[fname, read_items]
    #sats = @clk.satellites
    @clk.class.constants.each{|sys|
      next unless /^SYS_(?!SYSTEMS)(.*)/ =~ sys.to_s
      idx, sys_name = [@clk.class.const_get(sys), $1]
      #next unless sats[idx] > 0
      next unless @clk.push(@solver, idx)
      $stderr.puts "Change clock error source of #{sys_name} to RINEX clock" 
    }
  end
end

if __FILE__ == $0 then
  options = []
  misc_options = {}

  # check options and file format
  files = ARGV.collect{|arg|
    next [arg, nil] unless arg =~ /^--([^=]+)=?/
    k, v = [$1.downcase.to_sym, $']
    next [v, k] if [:rinex_nav, :rinex_obs, :ubx, :sp3, :antex, :rinex_clk].include?(k) # file type
    options << [$1.to_sym, $']
    nil
  }.compact

  options.reject!{|opt|
    case opt[0]
    when :start_time, :end_time
      require 'time'
      gpst_type = GPS::Time
      t = nil
      if opt[1] =~ /^(?:(\d+):)??(\d+(?:\.\d*)?)$/ then
        t = [$1 && $1.to_i, $2.to_f]
        t = gpst_type::new(*t) if t[0]
      elsif t = (Time::parse(opt[1]) rescue nil) then
        # leap second handling in Ruby Time is system dependent, thus 
        #t = gpst_type::new(0, t - Time::parse("1980-01-06 00:00:00 +0000"))
        # is inappropriate.
        subsec = t.subsec.to_f
        t = gpst_type::new(t.to_a[0..5].reverse)
        t += (subsec + gpst_type::guess_leap_seconds(t))
      else
        raise "Unknown time format: #{opt[1]}"
      end
      case t
      when gpst_type
        $stderr.puts(
            "#{opt[0]}: %d week %f (a.k.a %04d/%02d/%02d %02d:%02d:%02.1f)" \
              %(t.to_a + t.utc))
      when Array
        $stderr.puts("#{opt[0]}: #{t[0] || '(current)'} week #{t[1]}")
      end
      misc_options[opt[0]] = t
      true
    else
      false
    end
  }

  # Check file existence and extension
  files.collect!{|fname, ftype|
    raise "File not found: #{fname}" unless File::exist?(fname)
    ftype ||= case fname
    when /\.\d{2}n$/; :rinex_nav
    when /\.\d{2}o$/; :rinex_obs
    when /\.ubx$/; :ubx
    when /\.sp3$/; :sp3
    when /\.atx$/; :antex
    when /\.clk$/; :rinex_clk
    else
      raise "Format cannot be guessed, use --(format, ex. rinex_nav)=#{fname}"
    end
    [fname, ftype]
  }

  rcv = GPS_Receiver::new(options)

  proc{
    run_orig = rcv.method(:run)
    t_start, t_end = [nil, nil]
    tasks = []
    task = proc{|meas, t_meas, *args|
      t_start, t_end = [:start_time, :end_time].collect{|k|
        res = misc_options[k]
        res.kind_of?(Array) \
            ? GPS::Time::new(t_meas.week, res[1]) \
            : res
      }
      task = tasks.shift
      task.call(*([meas, t_meas] + args))
    }
    tasks << proc{|meas, t_meas, *args|
      next nil if t_start && (t_start > t_meas)
      task = tasks.shift
      task.call(*([meas, t_meas] + args))
    }
    tasks << proc{|meas, t_meas, *args|
      next nil if t_end && (t_end < t_meas)
      run_orig.call(*([meas, t_meas] + args))
    }
    rcv.define_singleton_method(:run){|*args|
      task.call(*args)
    }
  }.call if [:start_time, :end_time].any?{|k| misc_options[k]}

  puts rcv.header

  # parse RINEX NAV, SP3, or ANTEX
  files.each{|fname, ftype|
    case ftype
    when :rinex_nav; rcv.parse_rinex_nav(fname)
    when :sp3; rcv.attach_sp3(fname)
    when :antex; rcv.attach_antex(fname)
    when :rinex_clk; rcv.attach_rinex_clk(fname)
    end
  }
  
  # other files
  files.each{|fname, ftype|
    case ftype
    when :ubx; rcv.parse_ubx(fname)
    when :rinex_obs; rcv.parse_rinex_obs(fname)
    end
  }
end
