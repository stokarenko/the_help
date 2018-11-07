# TheHelp

TheHelp is a framework for developing service objects in a way that encourages
adherence to the [Single Responsibility Principle][SRP] and [Tell Don't
Ask][TDA]

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'the_help'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install the_help

## Usage

Create subclasses of [`TheHelp::Service`](lib/the_help/service.rb) and call
them.

Make it easier to call a service by including
[`TheHelp::ServiceCaller`](lib/the_help/service_caller.rb).

### Running Callbacks

This library encourages you to pass in callbacks to a service rather than
relying on a return value from the service call. For example:

```ruby
class Foo < TheHelp::Service
  authorization_policy allow_all: true

  main do
    call_service(GetSomeWidgets,
                 customer_id: 12345,
                 each_widget: callback(:process_widget),
                 invalid_customer: callback(:no_customer),
                 no_widgets_found: callback(:no_widgets))
    do_something_else
  end

  callback(:process_widget) do |widget|
    # do something with it
  end

  callback(:invalid_customer) do
    # handle this case
    stop!
  end

  callback(:no_widgets) do
    # handle this case
  end

  callback(:do_something_else) do
    # ...
  end
end
```

When writing a service that accepts callbacks like this, do not simply run
`#call` on the callback that was passed in. Instead you must use the
`#run_callback` method. This ensures that, if the callback method you pass in
tries to halt the execution of the service, it will behave as expected.

In the above service, it is clear that the intention is to stop executing the
`Foo` service in the case where `GetSomeWidgets` reports back that the customer
was invalid. However, if `GetSomeWidgets` is implemented as:

```ruby
class GetSomeWidgets < TheHelp::Service
  input :customer_id
  input :each_widget
  input :invalid_customer
  input :no_widgets_found

  authorization_policy allow_all: true

  main do
    set_some_stuff_up
    if customer_invalid?
      invalid_customer.call
      no_widgets_found.call
      do_some_important_cleanup_for_invalid_customers
    else
      #...
    end
  end

  #...
end
```

then the problem is that the call to `#stop!` in the `Foo#invalid_customer`
callback will not just stop the `Foo` service, it will also stop the
`GetSomeWidgets` service at the point where the callback is executed (because it
uses `throw` behind the scenes.) This would cause the
`do_some_important_cleanup_for_invalid_customers` method to never be called.

You can protect yourself from this by implementing `GetSomeWidgets` like this,
instead:

```ruby
class GetSomeWidgets < TheHelp::Service
  input :customer_id
  input :each_widget
  input :invalid_customer
  input :no_widgets_found

  authorization_policy allow_all: true

  main do
    set_some_stuff_up
    if customer_invalid?
      run_callback(invalid_customer)
      run_callback(no_widgets_found)
      do_some_important_cleanup_for_invalid_customers
    else
      #...
    end
  end

  #...
end
```

This will ensure that callbacks only stop the service that provides them, not
the service that calls them. (If you really do need to allow the calling service
to stop the execution of the inner service, you could raise an exception or
throw a symbol other than `:stop`; but do so with caution, since it may have
unintended consequences further down the stack.)

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run
`rake spec` to run the tests. You can also run `bin/console` for an interactive
prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To
release a new version, update the version number in `version.rb`, and then run
`bundle exec rake release`, which will create a git tag for the version, push
git commits and tags, and push the `.gem` file to
[rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/jwilger/the_help. This project is intended to be a safe,
welcoming space for collaboration, and contributors are expected to adhere to
the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT
License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the TheHelp project’s codebases, issue trackers, chat
rooms and mailing lists is expected to follow the [code of
conduct](https://github.com/jwilger/the_help/blob/master/CODE_OF_CONDUCT.md).

[SRP]: https://en.wikipedia.org/wiki/Single_responsibility_principle
[TDA]: https://martinfowler.com/bliki/TellDontAsk.html
