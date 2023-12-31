/**
 *
 * SylphideProcessorをswig経由で
 * スクリプトで使用するためのインターフェイスファイル
 *
 */

%module SylphideProcessor

%{
#include <string>

#include "SylphideProcessor.h"
%}

%include typemaps.i
%include std_string.i
%include exception.i

%exception {
  try {
    $action
  } catch (const std::exception& e) {
    SWIG_exception(SWIG_RuntimeError, e.what());
  }
}

%feature("autodoc", "1");

%define OBSERVER_COMMON_PREPROCESS(prefix)
%extend prefix ## _Packet_Observer{
  %ignore prefix ## _Packet_Observer;
  %alias ready "ready?";
  %alias validate "valid?";
}
%enddef

OBSERVER_COMMON_PREPROCESS(A);
OBSERVER_COMMON_PREPROCESS(F);
OBSERVER_COMMON_PREPROCESS(G);
OBSERVER_COMMON_PREPROCESS(P);
OBSERVER_COMMON_PREPROCESS(M);
OBSERVER_COMMON_PREPROCESS(N);

%fragment(SWIG_From_frag(short));
%fragment(SWIG_From_frag(unsigned short));
%fragment(SWIG_From_frag(unsigned int));
%header {
namespace swig {
  SWIG_Object from(const short &v) {return SWIG_From(short)(v);}
  SWIG_Object from(const unsigned short &v) {return SWIG_From(unsigned short)(v);}
  SWIG_Object from(const unsigned int &v) {return SWIG_From(unsigned int)(v);}
};
}

%extend array_t {
  %typemap(in,numinputs=0) const T **array_values (T *temp) "$1 = &temp;"
  %typemap(argout) const T **array_values {
    for(std::size_t i(0); i < N; ++i){
      %append_output(swig::from((*$1)[i]));
    }
  }
}
%inline %{
template <class T, std::size_t N>
struct array_t {
  private:
    const T (&ref)[N];
  public:
    array_t(const T (&ref_)[N]) : ref(ref_) {}
    T __getitem__(const unsigned &i) const {return ref[i];}
    void to_a(const T **array_values) const {
      *array_values = ref;
    }
};
%}

%template(SHORT_4elm) array_t<short, 4>;
%template(USHORT_4elm) array_t<unsigned short, 4>;
%template(UINT_8elm) array_t<unsigned int, 8>;

%inline %{
struct A_values_t {
  private:
    unsigned int _values[8];
  public:
    unsigned short temperature;
    array_t<unsigned int, 8> values() const {return array_t<unsigned int, 8>(_values);}
};
%}
%extend A_Packet_Observer{
  %ignore a_packet_size;
  %ignore fetch_values;
}

%inline %{
struct F_values_t {
  private:
    unsigned int _servo_in[8], _servo_out[8];
  public:
    array_t<unsigned int, 8> servo_in() const {return array_t<unsigned int, 8>(_servo_in);}
    array_t<unsigned int, 8> servo_out() const {return array_t<unsigned int, 8>(_servo_out);}
};
%}
%extend F_Packet_Observer{
  %ignore f_packet_size;
  %ignore fetch_values;
}

%inline %{
struct P_values_t {
  private:
    unsigned short _air_speed[4], _air_alpha[4], _air_beta[4];
  public:
    array_t<unsigned short, 4> air_speed() const {return array_t<unsigned short, 4>(_air_speed);}
    array_t<unsigned short, 4> air_alpha() const {return array_t<unsigned short, 4>(_air_alpha);}
    array_t<unsigned short, 4> air_beta() const {return array_t<unsigned short, 4>(_air_beta);}
};
%}
%extend P_Packet_Observer{
  %ignore fetch_values;
}

%inline %{
struct M_values_t {
  private:
    short _x[4], _y[4], _z[4];
  public:
    array_t<short, 4> x() const {return array_t<short, 4>(_x);}
    array_t<short, 4> y() const {return array_t<short, 4>(_y);}
    array_t<short, 4> z() const {return array_t<short, 4>(_z);}
};
%}
%extend M_Packet_Observer{
  %ignore fetch_values;
}

%inline %{
template <class FloatType>
struct G_position_t {
  FloatType longitude, latitude, altitude;
};
template <class FloatType>
struct G_position_acc_t {
  FloatType horizontal, vertical;
};
template <class FloatType>
struct G_velocity_t {
  FloatType north, east, down;
};
template <class FloatType>
struct G_velocity_acc_t {
  FloatType acc;      
};
template <class FloatType>
struct G_status_t {
  unsigned int fix_type;
  unsigned int status_flags;
  unsigned int differential;
  unsigned int time_to_first_fix_ms;
  unsigned int time_to_reset_ms;
  enum {
	    NO_FIX = 0,
	    DEAD_RECKONING_ONLY,
	    FIX_2D,
	    FIX_3D,
	    GPS_WITH_DR,
	    TIME_ONLY_FIX};
	enum {
	    FIX_OK = 0x01,
	    DGPS_USED = 0x02,
	    WN_VALID = 0x04,
	    TOW_VALID = 0x08};
};
template <class FloatType>
struct G_svinfo_t {
  unsigned int channel_num;
  unsigned int svid;
  unsigned int flags;
  unsigned int quality_indicator;
  int signal_strength;
  int elevation;
  int azimuth;
  int pseudo_residual;
};
template <class FloatType>
struct G_solution_t {
  short week;
  unsigned int fix_type;
  unsigned int status_flags;
  int position_ecef_cm[3];
  unsigned int position_ecef_acc_cm;
  int velocity_ecef_cm_s[3];
  unsigned int velocity_ecef_acc_cm_s;
  unsigned int satellites_used;
  enum {
      NO_FIX = 0,
      DEAD_RECKONING_ONLY,
      FIX_2D,
      FIX_3D,
      GPS_WITH_DR,
      TIME_ONLY_FIX};
  enum {
      FIX_OK = 0x01,
      DGPS_USED = 0x02,
      WN_VALID = 0x04,
      TOW_VALID = 0x08};
};
template <class FloatType>
struct G_utc_t {
  unsigned short year;
  unsigned char month;
  unsigned char day_of_month;
  unsigned char hour_of_day;
  unsigned char minute_of_hour;
  unsigned char seconds_of_minute;
  bool valid;
};
template <class FloatType>
struct G_raw_measurement_t {
  FloatType carrier_phase, pseudo_range, doppler;
  unsigned int sv_number;
  int quarity, signal_strength;
  unsigned int lock_indicator;
};
template <class FloatType>
struct G_ephemeris_t {
  unsigned int sv_number, how;
  bool valid;
  
  // Subframe 1
  unsigned int wn, ura, sv_health, iodc, t_oc;
  FloatType t_gd,  a_f2, a_f1, a_f0;
  
  // Subframe 2
  unsigned int iode, t_oe;
  FloatType c_rs, delta_n, m_0, c_uc, e, c_us, root_a;
  bool fit;
  
  // Subframe 3
  FloatType c_ic, omega_0, c_is, i_0, c_rc, omega, omega_0_dot, i_0_dot;
};
template <class FloatType>
struct G_health_t {
  bool healthy[32];
  bool valid;
};
template <class FloatType>
struct G_utc_param_t {
  FloatType a1, a0;
  unsigned int tot, wnt, ls, wnf, dn, lsf, spare;
  bool valid;  
};
template <class FloatType>
struct G_iono_t {
  FloatType klob_a0, klob_a1, klob_a2, klob_a3, klob_b0, klob_b1, klob_b2, klob_b3;
  bool valid;
};
template <class FloatType>
struct G_health_utc_iono_t {
  G_health_t<FloatType> health;
  G_utc_param_t<FloatType> utc_param;
  G_iono_t<FloatType> iono;
};
%}
%extend G_Packet_Observer{
  %ignore packet_type;
  %ignore fetch_position;
  %ignore fetch_position_hp;
  %ignore fetch_position_acc;
  %ignore fetch_position_acc_hp;
  %ignore fetch_velocity;
  %ignore fetch_velocity_acc;
  %ignore fetch_status;
  %ignore fetch_svinfo;
  %ignore fetch_solution;
  %ignore fetch_utc;
  %ignore fetch_raw;
  %ignore fetch_ephemeris;
  %ignore fetch_health_utc_iono;
}

%inline %{
template <class FloatType>
struct N_navdata_t {
  FloatType itow; // [s]
  FloatType latitude, longitude, altitude; // [deg], [deg], [m]
  FloatType v_north, v_east, v_down;  // [m/s]
  FloatType heading, pitch, roll; // [deg]
};
%}
%extend N_Packet_Observer{
  %ignore fetch_navdata;
}

%extend SylphideProcessor{
  %ignore set_a_handler;
  %ignore set_g_handler;
  %ignore set_f_handler;
  %ignore set_p_handler;
  %ignore set_m_handler;
  %ignore set_n_handler;
  void process(const std::string &s){
    self->process(const_cast<char *>(s.c_str()), s.size());
  }
}

%include SylphideProcessor.h

%define PROXY_TO_FUNC_WITH_NESTED_STRUCT(prefix, s_old, s_new, f_old, f_new)
%extend prefix ## _Packet_Observer{
  s_new f_new() const {
    union {
      prefix ## _Packet_Observer<FloatType>::s_old in;
      s_new out;
    } buf = {self->f_old()};
    return buf.out;
  }
}
%enddef

PROXY_TO_FUNC_WITH_NESTED_STRUCT(A, values_t, A_values_t, fetch_values, values);
PROXY_TO_FUNC_WITH_NESTED_STRUCT(F, values_t, F_values_t, fetch_values, values);
PROXY_TO_FUNC_WITH_NESTED_STRUCT(P, values_t, P_values_t, fetch_values, values);
PROXY_TO_FUNC_WITH_NESTED_STRUCT(M, values_t, M_values_t, fetch_values, values);
PROXY_TO_FUNC_WITH_NESTED_STRUCT(G, position_t, G_position_t<FloatType>, fetch_position, position);
PROXY_TO_FUNC_WITH_NESTED_STRUCT(G, position_t, G_position_t<FloatType>, fetch_position, position_hp);
PROXY_TO_FUNC_WITH_NESTED_STRUCT(G, position_acc_t, G_position_acc_t<FloatType>, fetch_position_acc, position_acc);
PROXY_TO_FUNC_WITH_NESTED_STRUCT(G, position_acc_t, G_position_acc_t<FloatType>, fetch_position_acc, position_acc_hp);
PROXY_TO_FUNC_WITH_NESTED_STRUCT(G, velocity_t, G_velocity_t<FloatType>, fetch_velocity, velocity);
PROXY_TO_FUNC_WITH_NESTED_STRUCT(G, velocity_acc_t, G_velocity_acc_t<FloatType>, fetch_velocity_acc, velocity_acc);
PROXY_TO_FUNC_WITH_NESTED_STRUCT(G, status_t, G_status_t<FloatType>, fetch_status, status);
PROXY_TO_FUNC_WITH_NESTED_STRUCT(G, solution_t, G_solution_t<FloatType>, fetch_solution, solution);
PROXY_TO_FUNC_WITH_NESTED_STRUCT(G, utc_t, G_utc_t<FloatType>, fetch_utc, utc);
PROXY_TO_FUNC_WITH_NESTED_STRUCT(G, ephemeris_t, G_ephemeris_t<FloatType>, fetch_ephemeris, ephemeris);
PROXY_TO_FUNC_WITH_NESTED_STRUCT(G, health_utc_iono_t, G_health_utc_iono_t<FloatType>, fetch_health_utc_iono, health_utc_iono);
%extend G_Packet_Observer{
  G_svinfo_t<FloatType> svinfo(unsigned int chn) const {
    union {
      G_Packet_Observer<FloatType>::svinfo_t in;
      G_svinfo_t<FloatType> out;
    } buf = {self->fetch_svinfo(chn)};
    return buf.out;
  }
  G_raw_measurement_t<FloatType> raw(unsigned int index) const {
    union {
      G_Packet_Observer<FloatType>::raw_measurement_t in;
      G_raw_measurement_t<FloatType> out;
    } buf = {self->fetch_raw(index)};
    return buf.out;
  }
  const unsigned int ubx_class() const {
    return self->operator[](2);
  }
  const unsigned int ubx_id() const {
    return self->operator[](3);
  }
  const unsigned int channels() const {
    return self->operator[](6 + 4);
  }
  const unsigned int num_of_sv() const {
    return self->operator[](6 + 6);
  }
}
PROXY_TO_FUNC_WITH_NESTED_STRUCT(N, navdata_t, N_navdata_t<FloatType>, fetch_navdata, navdata);

%extend SylphideProcessor{  
  %exception SylphideProcessor{
    $action
    result->set_a_handler(handler_A);
    result->set_g_handler(handler_G);
    result->set_f_handler(handler_F);
    result->set_p_handler(handler_P);
    result->set_m_handler(handler_M);
    result->set_n_handler(handler_N);
  }
  %exception process {
    if (!rb_block_given_p()) rb_raise(rb_eRuntimeError, "No block given");
    $action
  }
}

%define CONCRETIZE_OBSERVER(type, prefix)
%template(prefix ## PacketObserver) prefix ## _Packet_Observer<type>;
%fragment("handler"{prefix ## _Packet_Observer<type>}, "header") {
  static void handler_ ## prefix(const prefix ## _Packet_Observer<type> &obs){
    rb_yield(SWIG_NewPointerObj((void *)(&obs),
        $descriptor(prefix ## _Packet_Observer<type> &), 0));
  }
}
%fragment("handler"{prefix ## _Packet_Observer<type>});
%enddef

%define CONCRETIZE_PROCESSOR(type)
%template() Packet_Observer<type>;
CONCRETIZE_OBSERVER(type, A);
CONCRETIZE_OBSERVER(type, F);
%template(GPosition) G_position_t<type>;
%template(GPositionACC) G_position_acc_t<type>;
%template(GVelocity) G_velocity_t<type>;
%template(GVelocityACC) G_velocity_acc_t<type>;
%template(GStatus) G_status_t<type>;
%template(GSVInfo) G_svinfo_t<type>;
%template(GSolution) G_solution_t<type>;
%template(GUTC) G_utc_t<type>;
%template(GRaw) G_raw_measurement_t<type>;
%template(GEphemeris) G_ephemeris_t<type>;
%template(GHealth) G_health_t<type>;
%template(GUTCParam) G_utc_param_t<type>;
%template(GIono) G_iono_t<type>;
%template(GHUI) G_health_utc_iono_t<type>;
CONCRETIZE_OBSERVER(type, G);
//CONCRETIZE_OBSERVER(type, Data24Bytes);
CONCRETIZE_OBSERVER(type, P);
CONCRETIZE_OBSERVER(type, M);
%template(NNAV) N_navdata_t<type>;
CONCRETIZE_OBSERVER(type, N);
%template() AbstractSylphideProcessor<type>;
%template(SylphideLog) SylphideProcessor<type>;
%enddef

CONCRETIZE_PROCESSOR(double);

#undef CONCRETIZE_PROCESSOR
#undef CONCRETIZE_OBSERVER
