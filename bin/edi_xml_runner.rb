require_relative '../lib/alm_definitions.rb'
require_relative '../lib/alm_classes.rb'
require_relative '../lib/main.rb'

# exit if execution is part of build process
if Object.const_defined?(:Ocra)
	puts "Exiting #{File.basename(__FILE__)} during OCRA build process"
	exit
end

initialize_application

begin
	# begin monitoring for xml files
	watch_folder = $settings[:xml_watch_folder]
	puts "\n=====================================================\n".yellow
	plog "Starting to monitor [#{watch_folder.yellow}] for new xml files...\n"
	loop do
		xml_files = Dir.glob(watch_folder + '*.xml')
		if xml_files.empty?
			print "\r" + Time.now.ctime + " | No xml files found in watch folder: [#{watch_folder}]".blue
			sleep $settings[:wait_period].to_i
			next
		end
		plog "Found #{xml_files.count} xml files in folder. Executing tests..."
		run_edi_test
		puts "\n=====================================================\n".yellow
		plog "Resuming monitoring of [#{watch_folder.yellow}] for new xml files...\n"
	end
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
	plog report_error(e, "Error encountered in " + __FILE__.to_s.yellow)
	puts "Press enter to exit the application..."
	gets.chomp
ensure
	@test_sets.each{|t| t.stop_tests unless t.finished?} unless @test_sets.nil?
	disconnect_alm
end





