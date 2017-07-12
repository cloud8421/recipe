## CHANGELOG

### 0.4.2 (12/07/2017)

- Extends compile-time checks to check for `steps/0`

### 0.4.1 (07/07/2017)

- Adds `Recipe.unassign/2`
- Adds more examples of usage and configuration

### 0.4.0 (05/07/2017)

- Replaces log functionality with proper telemetry,
  which includes more hooks and execution time

### 0.3.0 (03/07/2017)

- Renames `Recipe.empty_state/0` to `Recipe.initial_state/0`
- Adds ability to use custom step log function

### 0.2.0 (02/07/2017)

- Removes `Recipe.run/1`
- Adds support for correlation ids
- Adds support to log steps at debug level

### 0.1.1 (30/06/2017)

- Recipes are checked at compile time to make sure that there's
  a step definition for each step

### 0.1.0 (30/06/2017)

- Initial release: can define and execute a recipe
