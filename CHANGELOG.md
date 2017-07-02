## CHANGELOG

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
