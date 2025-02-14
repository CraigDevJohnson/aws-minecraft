aws-minecraft
├── environments
│   ├── dev
│   │   ├── main.tf # later
│   │   ├── variables.tf # later
│   │   ├── outputs.tf # later
│   │   └── terraform.tfvars # later
│   └── prod
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars
├── modules
│   ├── compute
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── network
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── security
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── .gitignore
├── README.md
├── versions.tf
└── backend.tf


AWS Region: us-west-2