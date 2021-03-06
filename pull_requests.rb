#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require_relative 'octokit_utils'
require_relative 'options'

options = parse_options do |opts, result|
  opts.on('-a', '--after DAYS', 'Pull requests that were last updated after DAYS days ago.') { |v| result[:after] = v.to_i }
  opts.on('-b', '--before DAYS', 'Pull requests that were last updated before DAYS days ago.') { |v| result[:before] = v.to_i }
  opts.on('-c', '--count', 'Only print the count of pull requests.') { result[:count] = true }
  opts.on('-e', '--show-empty', 'List repos with no pull requests') { result[:empty] = true }
  opts.on('-s', '--sort', 'Sort output based on number of pull requests') { result[:sort] = true }
  opts.on('-v', '--verbose', 'More output') { result[:verbose] = true }

  opts.on('--no-response', 'Select PRs which had no response in the last 30 days') do
    result[:before] = 30
  end

  opts.on('--needs-closing', 'Select PRs where the last response is from an owner, but no further activity for the last 30 days') do
    result[:before] = 30
    result[:last_comment] = :owner
  end

  opts.on('--bad-status', 'Select PRs where the status is bad') do
    result[:bad_status] = 1
  end

  opts.on('--needs-squashed', 'Select PRs that need squashed') do
    result[:needs_squashed] = 1
  end

  opts.on('--needs-rebase', 'Select PRs where they need a rebase') do
    result[:needs_rebase] = 1
  end

  opts.on('--no-comments', 'Select PRs where there are no comments') do
    result[:no_comments] = 1
  end

  opts.on('--no-puppet-comments', 'Select PRs where there are no comments from puppet members') do
    result[:no_puppet_comments] = 1
  end

  opts.on('--last-comment-mention-member', 'Select PRs where the last comment mentions a puppet members') do
    result[:comment_mention_member] = 1
  end

  opts.on('--no-activity-40-days', 'Select PRs where there has been no activity in 40 days') do
    result[:no_activity_40] = 1
  end
end

parsed = load_url(options)
util = OctokitUtils.new(options[:oauth])

if options[:before] && options[:after]
  puts 'Only one of -a and -b can be specified'
  exit
end

repo_data = []

parsed.each do |_k, v|
  pr_information_cache = util.fetch_async((v['github']).to_s)
  begin
    pulls = if options[:last_comment] == :owner
              util.fetch_pull_requests_with_last_owner_comment(pr_information_cache)
            elsif options[:needs_rebase]
              util.fetch_pull_requests_which_need_rebase(pr_information_cache)
            elsif options[:bad_status]
              util.fetch_pull_requests_with_bad_status(pr_information_cache)
            elsif options[:needs_squashed]
              util.fetch_pull_requests_which_need_squashed(pr_information_cache)
            elsif options[:no_comments]
              util.fetch_uncommented_pull_requests(pr_information_cache)
            elsif options[:comment_mention_member]
              util.fetch_pull_requests_mention_member(pr_information_cache)
            elsif options[:no_puppet_comments]
              util.fetch_pull_requests_with_no_puppet_personnel_comments(pr_information_cache)
            elsif options[:no_activity_40]
              util.fetch_pull_requests_with_no_activity_40_days(pr_information_cache)
            else
              util.fetch_pull_requests((v['github']).to_s)
            end

    if options[:before]
      opts = { pulls: pulls }
      start_time = (DateTime.now - options[:before]).to_time
      pulls = util.pulls_older_than(start_time, opts)
    elsif options[:after]
      opts = { pulls: pulls }
      end_time = (DateTime.now - options[:after]).to_time
      pulls = util.pulls_newer_than(end_time, opts)
    end

    next if !(options[:empty]) && pulls.empty?

    repo_data << if options[:count]
                   { 'repo' => (v['github']).to_s, 'pulls' => nil, 'pull_count' => pulls.length }
                 else
                   { 'repo' => (v['github']).to_s, 'pulls' => pulls, 'pull_count' => pulls.length }
                 end
  rescue StandardError
    puts "Unable to fetch pull requests for #{v['github']}" if options[:verbose]
  end
end

repo_data.sort_by! { |x| -x['pull_count'] } if options[:sort]

repo_data.each do |entry|
  puts "=== #{entry['repo']} ==="
  case entry['pull_count']
  when 0
    puts '  no open pull requests'
  when 1
    puts '  1 open pull request'
  else
    puts "  #{entry['pull_count']} open pull requests"
  end
  next if options[:count]

  entry['pulls'].each do |pull|
    puts "  #{pull[:html_url]} - #{pull[:title]}"
  end
end
