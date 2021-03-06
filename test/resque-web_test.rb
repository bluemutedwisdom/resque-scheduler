# vim:fileencoding=utf-8
require_relative 'test_helper'

require 'resque/server/test_helper'

context 'on GET to /schedule' do
  setup { get '/schedule' }

  test('is 200') { assert last_response.ok? }
end

context 'on GET to /schedule with scheduled jobs' do
  setup do
    Resque::Scheduler.env = 'production'
    Resque.schedule = {
      'some_ivar_job' => {
        'cron' => '* * * * *',
        'class' => 'SomeIvarJob',
        'args' => '/tmp',
        'rails_env' => 'production'
      },
      'some_other_job' => {
        'every' => ['1m', ['1h']],
        'queue' => 'high',
        'custom_job_class' => 'SomeOtherJob',
        'args' => {
          'b' => 'blah'
        }
      },
      'some_fancy_job' => {
        'every' => ['1m'],
        'queue' => 'fancy',
        'class' => 'SomeFancyJob',
        'args' => 'sparkles',
        'rails_env' => 'fancy'
      },
      'shared_env_job' => {
        'cron' => '* * * * *',
        'class' => 'SomeSharedEnvJob',
        'args' => '/tmp',
        'rails_env' => 'fancy, production'
      }
    }
    Resque::Scheduler.load_schedule!
    get '/schedule'
  end

  test('is 200') { assert last_response.ok? }

  test 'see the scheduled job' do
    assert last_response.body.include?('SomeIvarJob')
  end

  test 'include(highlight) jobs for other envs' do
    assert last_response.body.include?('SomeFancyJob')
  end

  test 'includes job used in multiple environments' do
    assert last_response.body.include?('SomeSharedEnvJob')
  end

  test 'allows delete when dynamic' do
    Resque::Scheduler.stubs(:dynamic).returns(true)
    get '/schedule'

    assert last_response.body.include?('Delete')
  end

  test "doesn't allow delete when static" do
    Resque::Scheduler.stubs(:dynamic).returns(false)
    get '/schedule'

    assert !last_response.body.include?('Delete')
  end
end

module Test
  RESQUE_SCHEDULE = {
    'job_without_params' => {
      'cron' => '* * * * *',
      'class' => 'JobWithoutParams',
      'args' => {
        'host' => 'localhost'
      },
      'rails_env' => 'production'
    },
    'job_with_params' => {
      'every' => '1m',
      'class' => 'JobWithParams',
      'args' => {
        'host' => 'localhost'
      },
      'parameters' => {
        'log_level' => {
          'description' => 'The level of logging',
          'default' => 'warn'
        }
      }
    }
  }.freeze
end

context 'POST /schedule/requeue' do
  setup do
    Resque.schedule = Test::RESQUE_SCHEDULE
    Resque::Scheduler.load_schedule!
  end

  test 'job without params' do
    # Regular jobs without params should redirect to /overview
    job_name = 'job_without_params'
    Resque::Scheduler.stubs(:enqueue_from_config)
                     .once.with(Resque.schedule[job_name])

    post '/schedule/requeue', 'job_name' => job_name
    follow_redirect!
    assert_equal 'http://example.org/overview', last_request.url
    assert last_response.ok?
  end

  test 'job with params' do
    # If a job has params defined,
    # it should render the template with a form for the job params
    job_name = 'job_with_params'
    post '/schedule/requeue', 'job_name' => job_name

    assert last_response.ok?, last_response.errors
    assert last_response.body.include?('This job requires parameters')
    assert last_response.body.include?(
      %(<input type="hidden" name="job_name" value="#{job_name}">)
    )

    Resque.schedule[job_name]['parameters'].each do |_param_name, param_config|
      assert last_response.body.include?(
        '<span style="border-bottom:1px dotted;" ' <<
        %[title="#{param_config['description']}">(?)</span>]
      )
      assert last_response.body.include?(
        '<input type="text" name="log_level" ' <<
        %(value="#{param_config['default']}">)
      )
    end
  end
end

context 'POST /schedule/requeue_with_params' do
  setup do
    Resque.schedule = Test::RESQUE_SCHEDULE
    Resque::Scheduler.load_schedule!
  end

  test 'job with params' do
    job_name = 'job_with_params'
    log_level = 'error'

    job_config = Resque.schedule[job_name]
    args = job_config['args'].merge('log_level' => log_level)
    job_config = job_config.merge('args' => args)

    Resque::Scheduler.stubs(:enqueue_from_config).once.with(job_config)

    post '/schedule/requeue_with_params',
         'job_name' => job_name,
         'log_level' => log_level

    follow_redirect!
    assert_equal 'http://example.org/overview', last_request.url

    assert last_response.ok?, last_response.errors
  end
end
