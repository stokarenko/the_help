# TheHelp Changelog #

## 3.4.0 ##

* added `TheHelp::Service#delegate_to_service` method that can be used inside a service definition
  in order to have the current service delegate to another service and use the other service's
  result as its own.

## 3.3.0 ##

* Calling `#stop!` with no arguments in a service definition will now check that a result was set
  with either `#result.success` or `#result.error` and raise `TheHelp::NoResultError` if no result
  was set.

* You can now call `#stop!` with both a `type:` and `value:` argument. `type:` can be either
  `:error` (the default) or `:success`, and `value:` can be any object. Calling in this manner
  will set the service result to the specified type and value.
