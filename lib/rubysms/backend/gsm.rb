#!/usr/bin/env ruby
# vim: noet


# attempt to load rubygsm using relative paths first,
# so we can easily run on the trunk by cloning from
# github. the dir structure should look something like:
#
# projects
#  - rubygsms
#  - rubygsm
begin
	dir = File.dirname(__FILE__)
	dev_dir = "#{dir}/../../../rubygsm"
	dev_path = "#{dev_dir}/lib/rubygsm.rb"
	require File.expand_path(dev_path)
	
rescue LoadError
	begin
	
		# couldn't load via relative
		# path, so try loading the gem
		require "rubygems"
		require "rubygsm"
		
	rescue LoadError
		
		# nothing worked, so re-raise
		# with more useful information
		raise LoadError.new(
			"Couldn't load RubyGSM relatively (tried: " +\
			"#{dev_path.inspect}) or via RubyGems")
		
	end
end


module SMS::Backend
	
	# Provides an interface between RubyGSM and RubySMS,
	# which allows RubySMS to send real SMS in an abstract
	# fashion, which can be replicated by other backends.
	# This backend is probably the thinnest layer between
	# applications and the network, since the backend API
	# (first implemented here) was based on RubyGSM.
	class GSM < Base
		
		# just store the arguments until the
		# backend is ready to be started
		def initialize(port=:auto, pin=nil)
			@port = port
			@pin = nil
		end
		
		def start
			
			# lock the threads during modem initialization,
			# simply to avoid the screen log being mixed up
			Thread.exclusive do
				begin
					@gsm = ::Gsm::Modem.new(@port)
					@gsm.use_pin(@pin) unless @pin.nil?
					@gsm.receive method(:incoming)
					
					#bands = @gsm.bands_available.join(", ")
					#log "Using GSM Band: #{@gsm.band}MHz"
					#log "Modem supports: #{bands}"
					
					log "Waiting for GSM network..."
					str = @gsm.wait_for_network
					log "Signal strength is: #{str}"
					
				# couldn't open the port. this usually means
				# that the modem isn't plugged in to it...
				rescue Errno::ENOENT, ArgumentError
					log "Couldn't open #{@port}", :err
					raise IOError
					
				# something else went wrong
				# while initializing the modem
				rescue ::Gsm::Modem::Error => err
					log ["Couldn't initialize the modem",
						   "RubyGSM Says: #{err.desc}"], :err
					raise RuntimeError
				end
				
				# rubygsm didn't blow up?!
				log "Started GSM Backend", :init
			end
		end
		
		def send_sms(msg)
			super
			
			# send the message to the modem via rubygsm, and log
			# if it failed. TODO: needs moar info from rubygsm
			# on *why* sending failed
			unless @gsm.send_sms(msg.recipient.phone_number, msg.text)
				log "Message sending FAILED", :warn
			end
		end
		
		# called back by rubygsm when an incoming
		# message arrives, which we will pass on
		# to rubysms to dispatch to applications
		def incoming(msg)
			
			# NOTE: the msg argument is a GSM::Incoming
			# object from RubyGSM, NOT the more useful
			# SMS::Incoming object from RubySMS
			
			router.incoming(
				SMS::Incoming.new(
					self, msg.sender, msg.sent, msg.text))
		end
	end
end
