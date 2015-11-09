require_relative '../lib/main.rb'

app_start = Time.now

begin
	parent_folder = File.expand_path('..', __dir__)
	Dir.chdir(File.join(parent_folder, 'bin'))
	build_number = Time.now.strftime("%Y%m%d%H%M%S")
	puts "==============================".yellow
	puts "Creating build number: ".green + build_number.blue
	File.write(File.join(parent_folder, 'data', 'current_build_number.txt'), build_number)
	main_app_name = "edi_xml_main_app#{build_number}.exe"
	external_app_name = "edi_xml_wrapper#{build_number}.exe"
	File.open(File.join(parent_folder, 'data','build_history.txt'), 'a') { |f| f.write(Time.now.to_s + " | " + external_app_name + "\n") }
	lib_files = Dir.glob(File.join(parent_folder, 'lib', '*.rb')).join(' ')
	puts "==============================".yellow
	puts "Closing old processes and deleting old files...".red
	procs = ['EDI_XML_Monitor', 'edi_xml_wrapper', 'edi_xml_main_app']
	ProcTable.ps.each do |p|
		next if p.executable_path.nil?
		procs.each do |proc|
			if p.executable_path.include?(proc)
				puts "Closing process: #{p.pid} | #{p.executable_path}"
				command = 'taskkill /t /f /pid ' + p.pid.to_s
				output, error, status = Open3.capture3(command)
				puts "\tStatus: #{status}" unless status.to_s.empty?
				puts "\tError: #{error}" unless error.to_s.empty?
				puts "\tOutput: #{output}" unless output.to_s.empty?
			end
		end
	end
	executables = Dir.glob(File.join(parent_folder, 'bin', '*.exe')) + Dir.glob(File.join(parent_folder, '*.exe'))
	executables.each { |f| File.delete(f)}
	puts "==============================".yellow
	puts "Starting build of #{main_app_name}".cyan
	puts `ocra #{File.join(parent_folder, 'bin', 'edi_xml_runner.rb')} #{lib_files} #{File.join(parent_folder, 'res', 'paexec.exe')} #{File.join(parent_folder, 'data', '**')} --output #{main_app_name}`
	puts "==============================".yellow
	puts "Finished building #{main_app_name}".green
	puts "==============================".yellow
	puts "Starting build of #{external_app_name}".cyan
	puts `ocra #{File.join(parent_folder, 'bin', 'start_console_for_edi_runner.rbw')} #{main_app_name} #{File.join(parent_folder, 'res', 'ConEmuPortable', '**')} --output #{external_app_name}`
	puts "==============================".yellow
	puts "Finished building #{external_app_name}".green
	puts "==============================".yellow
	puts "\nCreation of build #{build_number.blue} is complete!"
	puts "Total build time: #{seconds_to_string(Time.now - app_start)}"
	final_location = parent_folder + '/EDI_XML_Monitor.exe'
	FileUtils.copy external_app_name, final_location
	puts "==============================".yellow
	puts "Executing file: #{final_location}".cyan
	Dir.chdir(parent_folder)
	system("start #{final_location}")
rescue => e
	puts report_error(e)
	binding.pry
end