require 'pry'
# exit if execution is part of build process
if Object.const_defined?(:Ocra)
	puts "Exiting #{File.basename(__FILE__)} during OCRA build process"
	exit
end
begin
	root = File.expand_path(File.dirname(__dir__))
	file = File.absolute_path(Dir.glob(File.join(root, 'bin', 'edi_xml_main_app*')).first)
	conemu = File.join(root, 'res','ConEmuPortable', 'ConEmu64.exe')
	command = "#{conemu} /cmd #{file}"
	system(command)
rescue Interrupt
	plog "\n\nInterrupting gracefully...\n".blue
	plog "The application was interrupted while in:\n\t".yellow + "#{__FILE__} | #{__method__}".blue
	puts "Press enter to exit the application..."
	gets.chomp
	# puts "Starting pry...".yellow
	# puts "A pry debugging session has been started. The application has been interrupted, presumably for debugging purposes. Anything done in this console will NOT be logged. Type exit to quit the debugging session and terminate the application.".green
	# binding.pry
	puts "Exiting application...".red
rescue => e
	plog report_error(e, "Error encountered in " + 'run_splits.rb'.yellow)
	puts "\nPress enter to exit the application...\n"
	gets.chomp
end
