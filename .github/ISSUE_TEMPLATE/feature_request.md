name: Feature Request
description: Suggest an idea or improvement
body:
  - type: markdown
    attributes:
      value: |
        Have an idea? Share it below!
  - type: textarea
    id: problem
    attributes:
      label: What problem does this solve?
      description: Describe the pain point or use case
    validations:
      required: true
  - type: textarea
    id: solution
    attributes:
      label: Proposed Solution
      description: How would you like this to work?
    validations:
      required: true
  - type: dropdown
    id: type
    attributes:
      label: Type
      options:
        - New database support
        - New feature
        - Improvement
        - Performance
        - Documentation
    validations:
      required: true
