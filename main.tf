provider "aws" {
	region = "ap-south-1"
	profile = "sky"
}

# -- Creating Key pairs

resource "tls_private_key" "key1" {
	algorithm = "RSA"
	rsa_bits = 4096
}

resource "local_file" "key2" {
	content = "${tls_private_key.key1.private_key_pem}"
	filename = "task1_key.pem"
	file_permission = 0400
}

resource "aws_key_pair" "key3" {
	key_name = "task2_key"
	public_key = "${tls_private_key.key1.public_key_openssh}"
}

# -- Creating Security Groups

resource "aws_security_group" "sg" {
	name        = "task2-sg"
  	description = "Allow TLS inbound traffic"
  	vpc_id      = "vpc-ebf8e583"


  	ingress {
    		description = "SSH"
    		from_port   = 22
    		to_port     = 22
    		protocol    = "tcp"
    		cidr_blocks = [ "0.0.0.0/0" ]
  	}

  	ingress {
    		description = "HTTP"
    		from_port   = 80
    		to_port     = 80
    		protocol    = "tcp"
    		cidr_blocks = [ "0.0.0.0/0" ]
  	}

  	egress {
    		from_port   = 0
    		to_port     = 0
    		protocol    = "-1"
    		cidr_blocks = ["0.0.0.0/0"]
  	}

  	tags = {
    		Name = "task2-sg"
  	}
}

# -- Creating Ec2 instance

resource "aws_instance" "web_server" {
  	ami = "ami-0447a12f28fddb066"
  	instance_type = "t2.micro"
	root_block_device {
		volume_type = "gp2"
		delete_on_termination = true
	}
  	key_name = "${aws_key_pair.key3.key_name}"
  	security_groups = [ "${aws_security_group.sg.name}" ]

  	connection {
    		type     = "ssh"
    		user     = "ec2-user"
    		private_key = "${tls_private_key.key1.private_key_pem}"
    		host     = "${aws_instance.web_server.public_ip}"
  	}

  	provisioner "remote-exec" {
    		inline = [
      			"sudo yum install httpd git -y",
      			"sudo systemctl restart httpd",
      			"sudo systemctl enable httpd",
    		]
  	}

  	tags = {
    		Name = "task2_os"
  	}

}

# -- Creating EFS volume

resource "aws_efs_file_system" "efs" {
   	creation_token = "efs"
   	performance_mode = "generalPurpose"
   	throughput_mode = "bursting"
   	encrypted = "true"
 	tags = {
     	Name = "Efs"
   	}
}

# -- Mounting the EFS volume

resource "aws_efs_mount_target" "efs-mount" {
	depends_on = [
		aws_instance.web_server,
		aws_security_group.sg,
		aws_efs_file_system.efs,
  	]
	
   	file_system_id  = "${aws_efs_file_system.efs.id}"
	subnet_id       = "${aws_instance.web_server.subnet_id}"
   	security_groups = ["${aws_security_group.sg.id}"]
	
	
  	connection {
    		type     = "ssh"
    		user     = "ec2-user"
   		private_key = "${tls_private_key.key1.private_key_pem}"
    		host     = "${aws_instance.web_server.public_ip}"
  	}

	provisioner "remote-exec" {
    		inline = [
      			"sudo mount ${aws_efs_file_system.efs.id}:/ /var/www/html",
   			"sudo echo '${aws_efs_file_system.efs.id}:/ /var/www/html efs defaults,_netdev 0 0' >> /etc/fstab",
      			"sudo rm -rf /var/www/html/*",
      			"sudo git clone https://github.com/Akashdeep-47/cloud_task2.git /var/www/html/"
    		]
	  }
}

# -- Creating S3 Bucket

resource "aws_s3_bucket" "mybucket"{
	bucket = "sky25"
	acl = "public-read"

	provisioner "local-exec" {
		command = "git clone https://github.com/Akashdeep-47/cloud_task2.git" 
	}
	
	provisioner "local-exec" {
		when = destroy 
		command = "echo y | rmdir /s cloud_task2"
	}
}

# -- Uploading files in S3 bucket

resource "aws_s3_bucket_object" "file_upload" {
	depends_on = [
    		aws_s3_bucket.mybucket,
  	]
  	bucket = "${aws_s3_bucket.mybucket.bucket}"
  	key    = "my_pic.jpg"
  	source = "cloud_task2/pic.jpg"
	acl ="public-read"
}

# -- Creating CloudFront

resource "aws_cloudfront_distribution" "s3_distribution" {
	depends_on = [
		aws_efs_mount_target.efs-mount,
    		aws_s3_bucket_object.file_upload,
  	]

	origin {
		domain_name = "${aws_s3_bucket.mybucket.bucket}.s3.amazonaws.com"
		origin_id = "ak" 
        }

	enabled = true
	is_ipv6_enabled = true
	default_root_object = "index.html"

	restrictions {
		geo_restriction {
			restriction_type = "none"
 		 }
 	    }

	default_cache_behavior {
		allowed_methods = ["HEAD", "GET"]
		cached_methods = ["HEAD", "GET"]
		forwarded_values {
			query_string = false
			cookies {
				forward = "none"
			}
		}
		default_ttl = 3600
		max_ttl = 86400
		min_ttl = 0
		target_origin_id = "ak"
		viewer_protocol_policy = "allow-all"
		}

	price_class = "PriceClass_All"

	 viewer_certificate {
   		 cloudfront_default_certificate = true
  	}		
}

# -- Updating cloudfront_url to main lacation 

resource "null_resource" "nullremote3"  {
	depends_on = [
    		aws_cloudfront_distribution.s3_distribution,
  	]

	connection {
    		type     = "ssh"
    		user     = "ec2-user"
   		private_key = "${tls_private_key.key1.private_key_pem}"
    		host     = "${aws_instance.web_server.public_ip}"
  	}
	
	provisioner "remote-exec" {
    		inline = [
			"sudo sed -i 's@twerk@http://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.file_upload.key}@g' /var/www/html/index.html",
			"sudo systemctl restart httpd"
    		]
	}
}

# -- Starting chrome for output

resource "null_resource" "nulllocal1"  {
	depends_on = [
    		null_resource.nullremote3,
  	]

	provisioner "local-exec" {
	    command = "start chrome  ${aws_instance.web_server.public_ip}"
  	}
}


