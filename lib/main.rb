require 'awesome_print'
require 'colorize'
require 'fileutils'
require 'ocra'
require 'open3'
require 'open-uri'
require 'pry'
require 'readline'
require 'terminal-table'
require 'win32ole'
require 'sys/proctable'
include Sys

def get_settings
	settings_file = File.join(Dir.pwd, 'settings.txt')
	unless File.exist?(settings_file)
		puts "\nNo settings file found at first location:\n".yellow + settings_file.cyan + "\n\nChecking second location...".yellow
		settings_file = File.expand_path(File.join('..', 'settings.txt'), __dir__)
	end
	unless File.exist?(settings_file)
		puts "\n\nSettings file does not exist at: \n".yellow + settings_file.cyan + "\n\nApplication cannot continue.".blue + "\n\nPlease ensure the settings.txt file is placed in the same directory as the application executable before running the aplication again".yellow + "\n\nExiting application...".red
		sleep 5
		exit
	end

	puts "\nSettings file found at:\n\t".yellow + settings_file.cyan
	contents = File.read(settings_file).split("\n")
	settings = {}
	contents.each do |setting|
		next if setting[0] == '#'
		next unless setting.include?('=')
		info = setting.split('=')
		settings.store(info.first.to_sym, info.last)
	end
	settings
end

def log(message, file=$logfile)
	stamped_message = "#{Time.now.strftime("%Y%m%d_%H%M%S")} | #{message}"
	File.open(file, "a") do |f|
		f.puts stamped_message.uncolorize
	end
	return
end

def plog(message, file=$logfile)
	stamped_message = "#{Time.now.strftime("%Y%m%d_%H%M%S")} | #{message}"
	File.open(file, "a") do |f|
		f.puts stamped_message.uncolorize
	end
	puts message
	return
end

def initialize_application
	$errors = []
	$settings = get_settings
	# logic to get windows username/password in case its needed to login to remote machines:
	# puts "Please enter the username to login to the execution machine:"
	# $settings.store(:username, gets.chomp)
	# puts "Please enter the password for user [#{$settings[:username]}]:"
	# $settings.store(:password, gets.chomp)
	$logfile = File.join(ENV['HOME'], 'Desktop', 'EDI_XML_Monitor', "EDI_XML_Monitor_Log_#{Time.now.strftime("%Y%m%d_%H%M%S")}.txt")
	unless File.exist?($logfile)
		FileUtils.mkdir_p(File.dirname($logfile)) unless File.directory?(File.dirname($logfile))
		plog "Creating log file:\n\t".yellow + $logfile.cyan
	end
	plog "Using build:\n\t".yellow + File.read(File.join(File.expand_path('..', __dir__), 'data', 'current_build_number.txt')).cyan
	longest = $settings.keys.join(' ').to_s.split.max_by(&:length).size + 4
	settings_info = ''
	$settings.each{|k, v| settings_info << "\t#{k.to_s.ljust(longest, '.').cyan}#{v.to_s.green}\n"}
	plog "Using the following settings from settings file:\n".yellow + settings_info
	$app_start = Time.now
	plog "Application initialization complete\nApplication log is located at:".green + "\n\t#{$logfile}".yellow
end

def get_hp_procs(host = nil)
	hp_procs = []
	a = host.nil? ? ProcTable.ps : ProcTable.ps(nil, host)
	a.each do |p|
		next if p.executable_path.nil?
		if p.executable_path.include?('\HP\\')
			hp_procs << p
		end
	end
	puts "No HP processes found!" if hp_procs.empty?
	hp_procs
end

def kill_all_hp_procs(host = nil)
	limit = host.nil? ? get_hp_procs.count : get_hp_procs(host).count
	counter = 0
	loop do
		hp_procs = host.nil? ? get_hp_procs : get_hp_procs(host)
		if hp_procs.empty?
			return true
		end
		counter += 1
		if counter > limit
			puts "Coudln't kill all HP processes"
			return false
		end
		puts "Killing process: #{hp_procs.first.pid} | #{hp_procs.first.executable_path}"
		if host.nil?
			command =  'taskkill /f /pid #{hp_procs.first.pid}'
		else
			command = File.expand_path(File.join('..', 'res','paexec.exe'), __dir__)
			command << " \\\\#{host} taskkill /F /S #{host} /pid #{hp_procs.first.pid}"
		end
		output, error, status = Open3.capture3(command)
		puts "\tStatus: #{status}" unless status.to_s.empty?
		puts "\tError: #{error}" unless error.to_s.empty?
		puts "\tOutput: #{output}" unless output.to_s.empty?
	end
end

def report_error(error, note = ' ')
	error_message = "\n=======================================================\n".light_red
	error_message << note.to_s.light_blue unless note.nil?
	# error_message << "\nMethod: ".ljust(12).cyan + __method__.to_s
	error_message << "\nTime: ".ljust(12).cyan + Time.now.localtime.to_s.green
	error_message << "\nComputer: ".ljust(12).cyan + @computer.green unless @computer.nil?
	error_message << "\nClass: ".ljust(12).cyan + error.class.to_s.light_red
	error_message << "\nMessage: ".ljust(12).cyan + error.message.light_red
	error_message << "\nBacktrace: ".ljust(12).cyan + error.backtrace.first.light_red
	error.backtrace[1..-1].each { |i| error_message << "\n           #{i.light_red}" }
	$errors.push "#{error_message}" unless $errors.nil?
	error_message
end

def pluralize(number)
	number == 1 ? "" : "s"
end

def seconds_to_string(seconds)
	# d = days, h = hours, m = minutes, s = seconds
	m = (seconds / 60).floor
	s = (seconds % 60).floor
	h = (m / 60).floor
	m = m % 60
	d = (h / 24).floor
	h = h % 24

	output = "#{s} second#{pluralize(s)}" if (s > 0)
	output = "#{m} minute#{pluralize(m)}, #{s} second#{pluralize(s)}" if (m > 0)
	output = "#{h} hour#{pluralize(h)}, #{m} minute#{pluralize(m)}, #{s} second#{pluralize(s)}" if (h > 0)
	output = "#{d} day#{pluralize(d)}, #{h} hour#{pluralize(h)}, #{m} minute#{pluralize(m)}, #{s} second#{pluralize(s)}" if (d > 0)
	return output
end

def make_table(rows, headings = nil)
	if headings.nil?
		table = Terminal::Table.new rows:rows
	else
		table = Terminal::Table.new headings:headings, rows:rows
	end
	return table
end

def spinner
	loop do
		['|', '/', '-', '\\'].each do |c|
			print "\r" + c+ "\t"
			sleep 0.1
		end
	end
end

def get_percent_complete(completed, total)
	percentage = completed.to_f / total.to_f * 100.to_f
	"#{percentage.round(1)}% complete...\t".rjust(5)
end