#!/usr/bin/ruby

class R_Bootstrap
  class <<self
    def registry_check(ver = nil)
      [:HKLM, :HKCU].collect{|head|
        `reg query "#{head}\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall" /f "R for Windows*is1" 2>nul`.scrub.lines
      }.flatten.collect{|line|
        next unless line.strip =~ /^\s*(.*#{ver}_is1)/
        $1
      }.compact
    end
    
    def setup_options(opt = {})
      r_ver = opt[:ver] || proc{
        require 'open-uri'
        if open("https://cran.r-project.org/bin/windows/base/release.htm").read \
            =~ /URL=R-(\d\.\d\.\d)-win\.exe/ then
          $1
        else
          raise "R version cannot be identified!"
        end
      }.call
      # Special care: working directory generated by ocra is different from executable
      dst_dir = opt[:dst_dir] \
          || File::join(File::dirname(File::absolute_path(
            ENV['OCRA_EXECUTABLE'] || __FILE__)), "R-#{r_ver}")
      arch = opt[:arch] || case `echo %PROCESSOR_ARCHITECTURE% `
        when /AMD64/; 'x64'
        when /x86/; `echo %PROCESSOR_ARCHITEW6432% ` =~ /AMD86/ ? 'x64' : 'i386'
        else; 'i386'
      end
      {
        :dst_dir => dst_dir,
        :r_ver => r_ver,
        :arch => arch,
        :src_url => "https://cloud.r-project.org/bin/windows/base/old/#{r_ver}/R-#{r_ver}-win.exe",
        :setup_inf => (<<-__TEXT__).gsub(/\R/, "\r\n"),
[Setup]
Dir=#{dst_dir}
Group=R
NoIcons=1
SetupType=custom
Components=main,#{arch},translations
Tasks=
[R]
MDISDI=MDI
HelpStyle=HTML
            __TEXT__
      }.merge(opt)
    end
    
    def check_installation(opt = {})
      opt = setup_options(opt)
      File::exist?(File::join(opt[:dst_dir], 'bin', opt[:arch], 'R.exe')) ? opt : nil
    end
    
    def setup(opt = {})
      opt = setup_options(opt)
      
      $stderr.print "0) Check previous installation of R #{opt[:r_ver]}: "
      checked = check_installation(opt)
      if checked then
        $stderr.puts "found, installation will be skipped."
        return checked
      else
        $stderr.puts "not found."
      end 
        
      require 'open-uri'
      require 'tempfile'
      
      $stderr.print "1) Downloading R #{opt[:r_ver]} installer"
      installer = open(opt[:src_url], 'rb',
          proc{
            len = nil
            step_bytes = 1_000_000
            steps = 0
            {
              :content_length_proc => proc{|content_length|
                len = content_length
                step_bytes = len / 100
              },
              :progress_proc => proc{|transferred_bytes|
                next_steps = (transferred_bytes / step_bytes).to_i
                (steps...next_steps).each{|i|
                  $stderr.print (i % 10 == 9 ? "#{i+1}#{(len ? "%" : "M")}" : ".")
                }
                steps = next_steps
              },
            }
          }.call){|io|
        $stderr.puts " done."
        
        Tempfile::open(['R-install', '.exe']){|io2|
          io2.binmode
          io2.write(io.read)
          io2.path
        }
      }
      FileUtils::chmod(0755, installer)
      
      setup_conf = Tempfile::open(['R-setup', '.inf']){|io|
        io.binmode
        io.print(opt[:setup_inf])
        io.path
      }
      
      # Check uninstaller registry entries before install
      reg_before_with_backup = Hash[*(registry_check(opt[:r_ver]).collect{|key|
        f = Tempfile::open(['R', '.reg']){|fp| fp}
        `reg export "#{key}" "#{f.path}" /y 2>nul`
        [key, f.open.read(0x4000)] # backup
      }.flatten(1))]
      
      cmd = "#{installer} /LOADINF=\"#{setup_conf}\" /SILENT"
      $stderr.print "2) Deploying R (#{cmd}) ..."
      system(cmd)
      $stderr.puts " done."
      
      # Remove newly generated uninstaller entry
      reg_after = registry_check(opt[:r_ver])
      (reg_after - reg_before_with_backup.keys).each{|key|
        `reg delete "#{key}" /f`
      }
      
      # Restore previous uninstaller entry
      (reg_after & reg_before_with_backup.keys).each{|key|
        f = Tempfile::open(['R', '.reg']){|fp|
          fp.binmode
          fp.write(reg_before_with_backup[key])
          fp
        }
        `reg import "#{f.path}" 2>nul`
      }
      
      # remove uninstaller binary, because it may remove registry 
      # required for uninstall of previously installed version.
      File::delete(*(["unins000.exe", "unins000.dat"].collect{|f| File::join(opt[:dst_dir], f)}))
      open(File::join(opt[:dst_dir], "README.uninstall"), "w"){|io|
        io.puts "To uninstall, just remove all files under this and sub directories"
      }
      
      check_installation(opt)
    end
  end
end

if $0 == __FILE__ then
  proc{ # for ocra, see https://www.cresco.co.jp/blog/entry/3213/
    cert_file = File.join(File.dirname($0), 'cert.pem')
    ENV['SSL_CERT_FILE'] = cert_file if File::exist?(cert_file)  
  }.call
  R_Bootstrap::setup
end

=begin
To make binary, cmd> ocra R_bootstrap.rb (path_to_ruby)\ssl\cert.pem --gem-minimal 
=end

__END__
require 'rinruby_without_r_constant'
r = RinRuby::new({
  :executable => File::join(r_dir, 'bin', 'x64', 'Rterm.exe'),
})
p r
r.prompt