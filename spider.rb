#!/bin/env ruby
# encoding:utf-8

require 'open-uri'
require 'thread'
require 'time'
require './htmlparser.rb'

class Handler
  def initialize(msg = nil)
		@msg = msg
	end

	def crawl(url, param = {}, code = 'utf-8')
		puts "[Crawl] #{url}"
		page = nil
		open(url, param) do |f|
			page = f.read
		end
		page.encode!(code, :invalid => :replace, :undef => :replace, :replace => "")
	end

	def download(url, param = {})
		puts "[Download] #{url} ... "
		data = nil
		open(url, param) do |f|
			data = f.read
		end
		data
	end

	def parse(page)
		HTMLParser::HTMLParser.new(page).parse
	end

	def handle(target)
		return {}
	end
end

class Task
	def initialize(target, handler)
		@thread = nil
		@finish = false
		@target = target
		@handler = handler
		@result = {}
		@retry = 0
		@max_retry_times = 2
	end

	def finish?
		@finish
	end

	def start
		@start_time = Time.now
		@thread = Thread.new do
			begin
				@result = @handler.handle(@target)
				@finish = true
			rescue Exception => e
				puts "[Exception] #{e}"
				@retry += 1
				restart
			end
		end
	end

	def pause
		Thread.kill(@thread)
		@thread = nil
	end

	def stop
		Thread.kill(@thread)
		@thread = nil
	end

	def restart
		stop
		@thread = Thread.new do
			begin
				@result = @handler.handle(@target)
				@finish = true
			rescue Exception => e
				puts "[Exception] #{e}"
				if @retry > @max_retry_times
					@finish = true
					puts "#Task failure for [{@target}]"
				else
					@retry += 1
					restart
				end
			end
		end
	end

	attr_reader :start_time, :result
end

class Spider
	def initialize
		@task_waiting_list = []
		@task_running_list = []
		@max_task_running = 10
		@timeout = 30.0
		@running = false
		@mutex = Mutex.new
	end

	def add_task(task)
		@mutex.synchronize do
			@task_waiting_list << task
		end
	end

	def run
		log "Spider is running ..."
		@running = true
		while @running and (@task_running_list.length > 0 or @task_waiting_list.length > 0)
			trap('SIGINT') do
				log 'System interrupted!'
				@running = false
			end

			new_tasks = []
			@mutex.synchronize do
				# finished task
				@task_running_list.delete_if do |task|
					if task.finish? and task.result != nil
						task.result.each do |target, handler|
							new_tasks << Task.new(target, handler)
						end
					end
					task.finish?
				end

				# timeout task
				now = Time.now
				timeout_task = []
				@task_running_list.each do |task|
					timeout_task << task if now - task.start_time > @timeout
				end
				timeout_task.each do |task|
					task.stop
					# @task_waiting_list << task
					@task_running_list.delete task
				end

				# new task
				while @task_running_list.length < @max_task_running and @task_waiting_list.length > 0
					task = @task_waiting_list.shift
					task.start
					@task_running_list << task
				end
			end

			new_tasks.each do |task|
				add_task(task)
			end

			puts "#{@task_running_list.length}/#{@task_running_list.length+@task_waiting_list.length} tasks is running"
			sleep 1
		end
		stop
	end

	def stop
		if @task_waiting_list.length == 0 and @task_running_list.length == 0
			log "All tasks are finished"
		end
		@task_running_list.each do |task|
			task.stop
		end
		log "Spider is stoped"
	end

	def log(msg)
		puts msg
	end
end
