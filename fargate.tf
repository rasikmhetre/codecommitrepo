provider "aws" {
  region = "us-east-1"
}
resource "aws_vpc" "fargatvpc" {
  cidr_block = "10.0.0.0/16"
}
resource "aws_subnet" "publicsubnet1" {
  vpc_id = aws_vpc.fargatvpc.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone = "us-east-1a"
}
resource "aws_subnet" "publicsubnet2" {
  vpc_id = aws_vpc.fargatvpc.id
  cidr_block = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone = "us-east-1b"
}
resource "aws_subnet" "privsub1" {
  vpc_id = aws_vpc.fargatvpc.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "us-east-1b"
}
resource "aws_subnet" "privsub2" {
  vpc_id = aws_vpc.fargatvpc.id
  cidr_block = "10.0.4.0/24"
  availability_zone = "us-east-1a"
}
resource "aws_internet_gateway" "ig" {
  vpc_id = aws_vpc.fargatvpc.id
}

resource "aws_ecs_cluster" "mycluster" {
 name = "nginx"
}


resource "aws_alb_target_group" "ecstargetgroup" {
  name     = "targategroup-nginx"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.fargatvpc.id
  target_type = "ip"
  depends_on = [aws_alb.nginxlb] 
}

#data "aws_iam_role" "ecs_task_execution_role" {
#  name = "ecsTaskExecutionRole"
#}
resource "aws_ecs_task_definition" "nginxtd" {
  family                = "nginxtd"
  container_definitions = file("task-definitions/service.json")
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu = "256"
  memory = "512"
  task_role_arn            = "${aws_iam_role.ecs_role.arn}"
  execution_role_arn       = "${aws_iam_role.ecs_role.arn}"
}

resource "aws_iam_role" "ecs_role" {
  name = "ECS_role"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
            "Service": [
                "ecs-tasks.amazonaws.com"
            ]
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}
resource "aws_iam_role_policy" "ecsrolepolicy" {
  name = "ecs_policy"


  role = "${aws_iam_role.ecs_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
      
        "ecs:DescribeContainerInstances",
        "ecs:DescribeTasks",
        "ecs:ListTasks",
        "ecs:UpdateContainerAgent",
        "ecs:StartTask",
        "ecs:StopTask",
        "ecs:RunTask",
        "ecs:DeleteCluster",
        "ecs:DeregisterContainerInstance",
        "ecs:ListContainerInstances",
        "ecs:RegisterContainerInstance",
        "ecs:SubmitContainerStateChange",
        "ecs:SubmitTaskStateChange",
        "ecr:GetAuthorizationToken",
         "ecr:BatchCheckLayerAvailability",
         "ecr:GetDownloadUrlForLayer",
         "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
                "ecr:ListImages",
             "ecr:DescribeImages",
                "ecr:BatchGetImage",
            "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:PutImage"


      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}
#==================================




resource "aws_ecs_service" "nginxservice" {
  name            = "nginxservice"
  cluster         = aws_ecs_cluster.mycluster.id
  task_definition = aws_ecs_task_definition.nginxtd.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  
  network_configuration {
    security_groups = [aws_security_group.ecs_task_sg.id]
    subnets         = [aws_subnet.privsub1.id,aws_subnet.privsub2.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.ecstargetgroup.arn
    container_name   = "tomcatapp"
    container_port   = 8080
  }
  depends_on      = [aws_alb.nginxlb]
}



resource "aws_alb" "nginxlb" {
name               = "nginxlb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = [aws_subnet.privsub1.id,aws_subnet.privsub2.id]
}
resource "aws_security_group" "lb_sg" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.fargatvpc.id
ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  
}
resource "aws_security_group" "ecs_task_sg" {
  name        = "allow_tls for ecs"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.fargatvpc.id
ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    security_groups = [aws_security_group.lb_sg.id]

  }
  
}

#=========Route Tables====================
resource "aws_route_table" "publicroute" {
  vpc_id = aws_vpc.fargatvpc.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ig.id
  }
}
resource "aws_route_table" "privateroute" {
  vpc_id = aws_vpc.fargatvpc.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.gw.id
  }
}



resource "aws_route_table_association" "privaterta1" {
  
  subnet_id = aws_subnet.privsub1.id
  route_table_id = aws_route_table.privateroute.id
}

resource "aws_route_table_association" "privaterta2" {
  
  subnet_id = aws_subnet.privsub2.id
  route_table_id = aws_route_table.privateroute.id
}
resource "aws_route_table_association" "publicrta1" {
  
  subnet_id = aws_subnet.publicsubnet2.id
  route_table_id = aws_route_table.publicroute.id
}
resource "aws_route_table_association" "publicrta2" {
  subnet_id = aws_subnet.publicsubnet1.id
  route_table_id = aws_route_table.publicroute.id
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_alb.nginxlb.id
  port = "80"
  protocol = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.ecstargetgroup.id
    type = "forward"
  }
}

#=======NAT GATEWAY=======

resource "aws_nat_gateway" "gw" {
  allocation_id = "${aws_eip.nat.id}"
  subnet_id     = "${aws_subnet.publicsubnet1.id}"
  depends_on = [aws_internet_gateway.ig]
}
#=========EIP=======

resource "aws_eip" "nat" {

}

#==============Code Commit================
resource "aws_codecommit_repository" "test" {
  repository_name = "tomcatapp"
  description     = "This is the tomcat App Repository"
  default_branch = "master"
}
#===========ECR============
resource "aws_ecr_repository" "tomcatapp" {
  name                 = "tomcatapp"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
#=======Codebuild======
resource "aws_codebuild_project" "tomcatbuild" {
  name          = "tomcatbuild"
  description   = "building image for tomcat application"
  build_timeout = "5"
  service_role  = "${aws_iam_role.code_build.arn}"


  artifacts {
    type = "NO_ARTIFACTS"
  }

  
  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:1.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode = "true"


    
  }

  logs_config {
    cloudwatch_logs {
      group_name = "log-group"
      stream_name = "log-stream"
    }

  }

  source {
    type            = "CODECOMMIT"
    location        = "https://git-codecommit.us-east-1.amazonaws.com/v1/repos/tomcatapp"
    git_clone_depth = 1
  }

#  vpc_config {
#    vpc_id = "${aws_vpc.tomcat.id}"
#
 #   subnets = [
 #     "${aws_subnet.tomcat1.id}",
 #     "${aws_subnet.tomcat2.id}",
 #   ]
#
#    security_group_ids = [
#      "${aws_security_group.tomcat1.id}",
#      "${aws_security_group.tomcat2.id}",
#    ]
#  }

  
#
}
resource "aws_iam_role" "code_build" {
  name = "codebuild_role"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
            "Service": [
                "codebuild.amazonaws.com"
            ]
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}
resource "aws_iam_role_policy" "codebuildpolicy" {
  name = "codebuild_policy"


  role = "${aws_iam_role.code_build.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "codecommit:GitPull",
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:GetRepositoryPolicy",
                "ecr:DescribeRepositories",
                "ecr:ListImages",
                "ecr:DescribeImages",
                "ecr:BatchGetImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:PutImage",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}
#=====IAM Codepipeline=====
resource "aws_s3_bucket" "codepipeline_bucketrasik" {
  bucket = "test-bucketrasik"
  acl    = "public-read"
}

resource "aws_iam_role" "codepipeline_role" {
  name = "codepipeline_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "codepipeline_policy"
  role = "${aws_iam_role.codepipeline_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
      "Effect": "Allow",
      "Action": [
        
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetBucketVersioning",
        "s3:PutObject",
        "codecommit:GitPull",
        "codecommit:GetBranch",
        "codecommit:GetRepository",
        "codecommit:GetCommit",
        "codecommit:GetRepositoryTriggers",
        "codecommit:UploadArchive",
        "codecommit:GetUploadArchiveStatus",
        "codecommit:BatchGetRepositories",
        "codecommit:UpdateDefaultBranch",
        "codecommit:UpdateRepositoryDescription ",
        "codecommit:CancelUploadArchive",
        "codecommit:GetBranch",
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:GetRepositoryPolicy",
        "ecr:DescribeRepositories",
        "ecr:ListImages",
        "ecr:DescribeImages",
        "ecr:BatchGetImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "ecs:DescribeTasks",
        "ecs:ListTasks",
        "ecs:UpdateContainerAgent",
        "ecs:StartTask",
        "ecs:StopTask",
        "ecs:RunTask",
        "ecs:DeleteCluster",
        "ecs:DeregisterContainerInstance",
        "ecs:ListContainerInstances",
        "ecs:RegisterContainerInstance",
        "ecs:SubmitContainerStateChange",
        "ecs:SubmitTaskStateChange",
        "s3:PutObject",
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetBucketVersioning"
        

      ],
      "Resource": [

        "${aws_s3_bucket.codepipeline_bucketrasik.arn}",
        "${aws_s3_bucket.codepipeline_bucketrasik.arn}/*",
        "*"
        

        ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild",
        "codebuild:CreateProject",
        "codebuild:UpdateProject"
      ],
       "Resource": "*"

    },


    {
            "Effect": "Allow",
            "Action": [
                "codecommit:GitPull",
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:GetRepositoryPolicy",
                "ecr:DescribeRepositories",
                "ecr:ListImages",
                "ecr:DescribeImages",
                "ecr:BatchGetImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:PutImage",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "codecommit:GitPull",
        "codecommit:GetBranch",
        "codecommit:GetRepository",
        "codecommit:GetCommit",
        "codecommit:GetRepositoryTriggers",
        "codecommit:UploadArchive",
        "codecommit:GetUploadArchiveStatus",
        "codecommit:BatchGetRepositories",
        "codecommit:UpdateDefaultBranch",
        "codecommit:UpdateRepositoryDescription ",
        "codecommit:CancelUploadArchive",
        "codecommit:GetBranch"
            ],
            "Resource": "*"
      }

]

}
EOF
}

data "aws_kms_alias" "s3" {
  name = "alias/aws/s3"
}

resource "aws_kms_key" "a" {
  description             = "KMS key 1"
  deletion_window_in_days = 7
}

resource "aws_codepipeline" "codepipeline" {
  name     = "tf-test-pipeline"
  role_arn = "${aws_iam_role.codepipeline_role.arn}"

  artifact_store {
    location = "${aws_s3_bucket.codepipeline_bucketrasik.bucket}"
    type     = "S3"
  encryption_key {
      id   = "${data.aws_kms_alias.s3.arn}"
      type = "KMS"
    }
    
  }



  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["source"]

      configuration = {
        RepositoryName = "tomcatapp"
        BranchName     = "master"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source"]
      output_artifacts = ["imagedefinitions"]
      version          = "1"

      configuration = {
        ProjectName = "tomcatbuild"
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      input_artifacts = ["imagedefinitions"]
      version         = "1"
      
      configuration = {
        ClusterName = "nginx"
        ServiceName = "nginxservice"
        FileName    = "imagedefinitions.json"
      }
    }
  }
}
