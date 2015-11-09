class Test
	attr_accessor :company, :test_set, :test_set_id, :name, :automation_status, :run_status, :run_date, :subject, :test_object, :test_id, :last_run_id, :headers, :has_been_run

	def initialize(test, test_set, test_set_id)
		test.Refresh
		@test_object = test
		@name = test.Name[3..-1]
		@automation_status =  test.Field('TS_STATUS')
		@subject = test.Field('TS_SUBJECT').Path.split('\\').last
		@test_id = test.ID.to_i
		@test_set = test_set
		@test_set_id = test_set_id.to_i
		@run_date = "not polled"
		@run_duration = "not polled"
		@run_status = "not polled"
		@last_run_id = "not polled"
		@headers = ['Company', 'Test Set', 'Test Name', 'Automation Status', 'Run Date', 'Run Status', 'Subject', 'Test ID', 'Last Run ID']
		if @name.include?('CDW')
			case
			when @name.include?('CDWG') || @name[-2..-1] == '_G'
				@company = 'CDWG'
			when @name.include?('CDWCA') || @name[-3..-1] == '_CA'
				@company = 'CDWCA'
			else
				@company = 'CDW'
			end
		else
			@company = 'N/A'
		end
	end

	def refresh_run_status
		@test_object.Refresh
		if @test_object.LastRun.nil?
			@run_date = "test has not been run"
			@run_duration = "test has not been run"
			@run_status = "test has not been run"
			@last_run_id = "test has not been run"
		else
			@run_date = "#{@test_object.LastRun.Field("RN_EXECUTION_DATE").to_s[0..9]}_#{@test_object.LastRun.Field("RN_EXECUTION_TIME")}"
			@run_duration = seconds_to_string(@test_object.LastRun.Field("RN_DURATION").to_i)
			@run_status = @test_object.LastRun.Field("RN_STATUS")
			@last_run_id = @test_object.LastRun.Field("RN_RUN_ID").to_i
		end
		return [@name, @test_id, @run_date, @run_status, @last_run_id]
	end

	def display_variables
		refresh_run_status
		length = self.instance_variables.max_by(&:length).length
		self.instance_variables.sort.each_with_index do |v, i|
			name = v.to_s[1..-1].ljust(length)
			variable = self.instance_variable_get(v)
			puts "#{name}| #{variable}"
		end
	end

	def display_info
		refresh_run_status
		puts make_table(info.join(" | "), @headers)
	end

	def info
		refresh_run_status
		# return [@company.cyan, @test_set.yellow, @name, @automation_status.cyan, @run_date.yellow, @run_status == "Passed"? @run_status.green : @run_status.red, @subject, @test_id, @last_run_id]
		return [@company, @test_set, @name, @automation_status, @run_date, @run_status, @subject, @test_id, @last_run_id]
	end

	def display_last_run_info
		puts make_table(refresh_run_status, ['Name', 'Test ID', 'Run Date', 'Run Status', 'Last Run ID'])
	end

	def plain_data
		"#{@company}\t#{@test_set}\t#{@name}\t#{@automation_status}\t#{@run_date}\t#{@run_status}\t#{@subject}\t#{@test_id}\t#{@last_run_id}"
	end

	def last_run_status
		@test_object.Refresh
		@test_object.LastRun.Field("RN_STATUS")
	end

	def get_failed_steps
		refresh_run_status
		steps = @test_object.LastRun.StepFactory.NewList("")
		step_info = []
		steps.each do |s|
			step_info.push [@company, @test_set, @name, @run_date, @last_run_id, s.Name, s.Field('ST_DESCRIPTION'), s.Status] if s.Status == 'Failed'
			$failed_steps.push s if s.HasAttachment
		end
		step_info
	end
end

class Test_Set
	attr_reader :tests, :name, :id, :scheduler, :test_set_object, :fail_data, :fail_count
	attr_accessor :hosts, :execution_start_time, :test_filter

	def initialize(test_set, test_filter)
		@scheduler = nil
		@test_set_object = test_set
		@name = test_set.Name
		@id = test_set.ID
		@tests = []
		@test_filter = test_filter
	end

	def add_test(test)
		@tests.push test
	end

	def run_tests
		@test_set_object.AutoPost = true
		@test_set_object.ExecutionReportSettings.Enabled = true
		@tests.each do |t|
			# reset run status to N/A. This ensures all tests have a status of 'not run'
			# before starting execution. That allows us to easily keep track of tests that were not run
			t.test_object['TC_STATUS'] = 'N/A'
			t.test_object.Post
		end
		@scheduler = @test_set_object.StartExecution("")
		# needs to be able to split test into groups for running on multiple hosts
		if @hosts.nil?
			plog "Running tests on local machine."
			@scheduler.RunAllLocally = true
		else
			if @hosts.count == 1
				plog "Running tests on machine [#{@hosts.first.yellow}]"
				@scheduler.TdHostName = @hosts.first
			else
				plog "running on multiple hosts not yet implemented!".red
				@scheduler = nil
				return false
			end
		end
		@scheduler.LogEnabled = true
		@execution_start_time = Time.now
		# @scheduler.Run(run_list)
		@scheduler.Run(@test_filter)
		plog "Beginning execution of [#{@tests.count.to_s.yellow}] tests in set [#{@name.yellow}]"
	rescue => e
		plog report_error(e, "Error encountered in [#{__method__.to_s}]")
	end

	def stop_tests(tests = nil)
		if @scheduler.nil?
			plog "Cannot stop tests if tests have not been run yet!"
			return false
		end
		if finished?
			plog "Test set execution has already completed, cannot stop tests"
			return false
		end
		# needs to be able to stop all tests or individual tests
		if tests.nil?
			plog "Stoping all tests in test set #{@name}"
			@tests.each do |test|
				# need to check return value here and create a check for succesffully stopped or not(if possible)
				result = @scheduler.Stop(test.test_id.to_s)
				plog "Stopping test [#{test.name.yellow}] | #{result}"
			end
		else
			plog "Stopping individual tests is not yet implemented!"
		end
	rescue => e
		plog report_error(e, "Error encountered in [#{__method__.to_s}]")
	end

	def finished?
		if @scheduler.nil?
			plog "Test set [#{@name}] has not been run yet."
			return false
		end
		run_status = @scheduler.ExecutionStatus
		run_status.RefreshExecStatusInfo("all", true)
		run_status.Finished
	end

	def display_test_status
		if @scheduler.nil?
			puts "Test set [#{@name}] has not been run yet."
			return false
		end
		all_tests_status = []
		run_status = @scheduler.ExecutionStatus
		run_status.RefreshExecStatusInfo("all", true)
		running_counter = 0
		passed_counter = 0
		failed_counter = 0
		not_run_counter = 0
		other_counter = 0
		error_counter = 0
		puts "\nStatus for #{run_status.Count.to_s.yellow} tests in [#{@name}]:"
		plog finished? ? "Tests execution is complete!".cyan : "Tests are still running...".yellow
		(1..run_status.count).each do |i|
			run_instance = run_status.Item(i)
			name = '-----'
			status = run_instance.Status
			message = run_instance.Message
			testid = run_instance.TestID
			tstestid = run_instance.TSTestID
			@tests.each{|t| name = t.name if t.test_id.to_i == tstestid.to_i} # Loop to get name of test
			case status
			when 'Running'
				running_counter += 1
			when "FinishedPassed"
				passed_counter += 1
			when "FinishedFailed"
				failed_counter += 1
			when 'Waiting'
				not_run_counter += 1
			when "Error"
				error_counter += 1
			else
				other_counter += 1
			end
			all_tests_status.push [i, name, status, message, testid, tstestid]
		end
		result = []
		result << 'Running: '.ljust(10).yellow + running_counter.to_s.yellow
		result << "Passed: ".ljust(10).green + passed_counter.to_s.green
		result << "Failed: ".ljust(10).red + failed_counter.to_s.red
		result << "Not Run: ".ljust(10).yellow + not_run_counter.to_s.yellow
		result << "Error: ".ljust(10).red + error_counter.to_s.red
		result << "Other: ".ljust(10).blue + other_counter.to_s.blue
		result << make_table(all_tests_status, ['Test#', 'Name', 'Status', 'Message', 'TestID', 'TSTestID'])
		return result.join("\n")
	rescue => e
		plog report_error(e, "Error encountered in [#{__method__.to_s}]")
		binding.pry
	end

	def display_tests
		headers = tests.first.headers
		all_test_info = []
		@tests.each do |test|
			all_test_info << test.info
		end
		puts "Test set [#{@name}] includes [#{@tests.count}] tests:"
		puts make_table(all_test_info, headers)
	end

	def display_run_log
		if @scheduler.nil?
			puts "Cannot display test run log if tests aren't running!"
			return false
		end
		puts "Test set has been running for #{seconds_to_string(Time.now - @execution_start_time).cyan}"
		@scheduler.ExecutionStatus.RefreshExecStatusInfo("all", true)
		log_items = @scheduler.ExecutionLog.gsub("}\r\n\r\n{", '|||').gsub("\r\n", '')[1..-2].split('|||')
		parsed_log = []
		log_items[1..-1].each do |item|
			temp = []
			item.split(',').each do |value|
				temp.push value.split(': ').last.split('\\').last.sub('[1]', '').gsub('"', '')
			end
			parsed_log.push temp
		end
		puts "#{log_items.first.gsub(',', "\n").cyan}\n#{make_table(parsed_log, ['Type', 'Date/Time', 'Test ID', 'Test Name', 'Host', 'Status'])}".yellow
	rescue => e
		plog report_error(e, "Error encountered in [#{__method__.to_s}]")
	end

	def get_failed_tests(date=nil)
		fail_data = []
		fail_count = 0
		@tests.each_with_index do |t, i|
			print "\r" + get_percent_complete(i + 1, @tests.count).green + " | Getting failed tests for test set " + @name.blue
			if t.last_run_status == 'Failed'
				t.refresh_run_status
				unless date.nil?
					d1 = Date.parse(date) rescue false
					d2 = Date.parse(t.run_date) rescue false
					message = []
					message << "date(#{date}) could not be parsed as a date" unless d1
					message << "t.run_date(#{t.run_date}) could not be parsed as a date" unless d2
					unless message.empty?
						message.unshift("get_failed_tests:".yellow + " There was an issue parsing the provided date information!".red) unless message.empty?
						next
					end
					next unless Date.parse(date) < Date.parse(t.run_date)
				end
				fail_data.concat t.get_failed_steps
				fail_count += 1
			end
		end
		@fail_data = fail_data
		@fail_count = fail_count
		return fail_data
	end
end
