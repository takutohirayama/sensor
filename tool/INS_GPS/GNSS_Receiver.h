/*
 * Copyright (c) 2020, M.Naruoka (fenrir)
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * - Redistributions of source code must retain the above copyright notice,
 *   this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * - Neither the name of the naruoka.org nor the names of its contributors
 *   may be used to endorse or promote products derived from this software
 *   without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 * OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
 * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */

#ifndef __GNSS_RECEIVER_H__
#define __GNSS_RECEIVER_H__

#include <iostream>

#include "navigation/GPS.h"
#include "navigation/GPS_Solver.h"
#include "navigation/RINEX.h"

#include "INS_GPS/GNSS_Data.h"

#include "analyze_common.h"

template <class FloatT>
struct GNSS_Receiver {
  typedef GPS_SpaceNode<FloatT> gps_space_node_t;
  typedef GPS_SinglePositioning<FloatT> gps_solver_t;

  struct data_t {
    struct {
      gps_space_node_t space_node;
      typename gps_solver_t::options_t solver_options;
    } gps;
    std::ostream *out_rinex_nav;
    data_t() : gps(), out_rinex_nav(NULL) {}
    ~data_t(){
      if(out_rinex_nav){
        RINEX_NAV_Writer<FloatT>::write_all(*out_rinex_nav, gps.space_node);
      }
    }
  } data;

  struct solvers_t {
    gps_solver_t gps;
    solvers_t(const GNSS_Receiver &rcv)
        : gps(rcv.data.gps.space_node, rcv.data.gps.solver_options)
        {}
  } solvers;

  GNSS_Receiver() : data(), solvers(*this) {}
  GNSS_Receiver(const GNSS_Receiver &another)
      : data(another.data), solvers(*this) {}
  GNSS_Receiver &operator=(const GNSS_Receiver &another){
    data = another.data;
    return *this;
  }

  void setup(typename GNSS_Data<FloatT>::Loader &loader) const {
    loader.gps = &const_cast<gps_space_node_t &>(data.gps.space_node);
  }

  const GPS_Solver_Base<FloatT> &solver() const {
    return solvers.gps;
  }

  void adjust(const GPS_Time<FloatT> &t){
    // Select most preferable ephemeris
    data.gps.space_node.update_all_ephemeris(t);

    // Solver update mainly for preferable ionospheric model selection
    // based on their availability
    solvers.gps.update_options(data.gps.solver_options);
  }

  typedef GlobalOptions<FloatT> runtime_opt_t;

  bool check_spec(
      runtime_opt_t &options,
      const char *spec, const bool &dry_run = false){
    const char *value;

    if(value = runtime_opt_t::get_value(spec, "rinex_nav", false)){
      if(dry_run){return true;}
      std::cerr << "RINEX Navigation file (" << value << ") reading..." << std::endl;
      std::istream &in(options.spec2istream(value));
      int ephemeris(RINEX_NAV_Reader<FloatT>::read_all(
          in, data.gps.space_node));
      if(ephemeris < 0){
        std::cerr << "(error!) Invalid format!" << std::endl;
        return false;
      }else{
        std::cerr << "rinex_nav: " << ephemeris << " items captured." << std::endl;
      }
      return true;
    }
    if(value = runtime_opt_t::get_value(spec, "out_rinex_nav", false)){
      if(dry_run){return true;}
      data.out_rinex_nav = &options.spec2ostream(value);
      std::cerr << "out_rinex_nav: " << value << std::endl;
      return true;
    }

    if(value = runtime_opt_t::get_value(spec, "F10.7", false)){
      if(dry_run){return true;}
      FloatT f_10_7(atof(value));
      if((f_10_7 <= 0) || (f_10_7 > 1E3)){
        std::cerr << "(error!) Abnormal F10.7!" << value << std::endl;
        return false;
      }
      std::cerr << "F10.7: " << f_10_7 << std::endl;
      data.gps.solver_options.f_10_7 = f_10_7;
      data.gps.solver_options.insert_ionospheric_model(
          gps_solver_t::options_t::IONOSPHERIC_NTCM_GL);
      return true;
    }
    return false;
  }
};

#endif /* __GNSS_RECEIVER_H__ */