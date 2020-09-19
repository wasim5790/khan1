provider "aws" {
       profile= "default"
       region = "ap-south-1"
}

#creating vpc:

resource "aws_vpc" "myvpc" {
  cidr_block       = "192.168.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = true
}

resource "aws_subnet" "publicsubnet" {
  vpc_id     = "${aws_vpc.myvpc.id}"
  cidr_block = "192.168.0.0/24"
  availability_zone = "ap-south-1a"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "mygate" {
  vpc_id = "${aws_vpc.myvpc.id}"
}

resource "aws_route_table" "my-rt" {
  vpc_id = "${aws_vpc.myvpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.mygate.id}"
  }
}

resource "aws_route_table_association" "public-rt" {
  subnet_id      = aws_subnet.publicsubnet.id
  route_table_id = aws_route_table.my-rt.id
}

resource "aws_security_group" "efs-sg" {
  vpc_id      = "${aws_vpc.myvpc.id}"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  } 
  
  ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#Creating the Elastic File System (EFS):

resource "aws_efs_file_system" "myefs" {
}

resource "aws_efs_mount_target" "efs-tar" {
  file_system_id = "${aws_efs_file_system.myefs.id}"
  subnet_id      = "${aws_subnet.publicsubnet.id}"
  security_groups = ["${aws_security_group.efs-sg.id}"]
}

#Creating the Instance:

resource "aws_instance" "efs-demo" {
ami           = "ami-08706cb5f68222d09"
instance_type = "t2.micro"
key_name      = "newkey"
subnet_id     = "${aws_subnet.publicsubnet.id}" 
vpc_security_group_ids = ["${aws_security_group.efs-sg.id}"]
user_data = <<-EOF

   	#! /bin/bash
	sudo su - root
	sudo yum install httpd -y
        sudo service httpd start
	sudo service httpd enable
 	sudo yum install git -y
        sudo yum install -y amazon-efs-utils 
        sudo mount -t efs "${aws_efs_file_system.myefs.id}":/ /var/www/html
	mkfs.ext4 /dev/sdf	
	mount /dev/sdf /var/www/html
	cd /var/www/html
	git clone https://github.com/wasim5790/khan1.git
	  
EOF
}

#Creating s3 bucket and bucket object:

resource "aws_s3_bucket" "wasim16" {
  bucket = "wasim16"
  acl    = "public-read"
}

resource "aws_iam_role" "codepipeline_role" {
  name = "test-role1"

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
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetBucketVersioning",
        "s3:PutObject"
      ],
      "Resource": [
        "${aws_s3_bucket.wasim16.arn}",
        "${aws_s3_bucket.wasim16.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_codepipeline" "codepipeline" {
  name     = "shubhampipeline"
  role_arn = "${aws_iam_role.codepipeline_role.arn}"

  artifact_store {
    location = "${aws_s3_bucket.wasim16.bucket}"
    type     = "S3"
    }
  

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["SourceArtifact"]

      configuration = {
        Owner  = "shubh016"
        Repo   = "khan11"
        Branch = "master"
	OAuthToken = " 5e06a0fbf9bb0d748953cdc4e38955c970a461a6"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "S3"
      input_artifacts = ["SourceArtifact"]
      version         = "1"

      configuration = {
        BucketName = "${aws_s3_bucket.wasim16.bucket}"
	Extract = "true"
        OjectKey = "/*.jpg"
      }
    }
  }
}

#creating cloudfront distribution:



resource "aws_cloudfront_distribution" "s3_distribution" {
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "aws_s3_bucket.wasim16.bucket"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
  }
enabled = true
origin {
        domain_name = "${aws_s3_bucket.wasim16.bucket_domain_name}"
        origin_id   = "aws_s3_bucket.wasim16.bucket"
    }

restrictions {
        geo_restriction {
        restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}