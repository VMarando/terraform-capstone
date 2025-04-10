# **Capstone Project: Automated Cloud Infrastructure Provisioning with Terraform**

This repository contains a capstone project focused on **automating the provisioning of cloud infrastructure** on **AWS** using **Terraform**. The project demonstrates how to deploy and manage essential AWS resources, such as **EC2 instances**, **S3 buckets**, **VPCs**, **subnets**, and **security groups**, all through the **Terraform Cloud web interface**.

## **Project Overview**

The goal of this project is to automate the deployment of various AWS resources required by a business application. By using **Terraform**, the project simplifies the process of managing cloud infrastructure while ensuring scalability and consistency. The infrastructure is modular, allowing for flexible and reusable deployments that can meet different business needs.

### **Key Features:**

- **Automated EC2 Instance Provisioning**: Deploy scalable compute resources for applications.
- **VPC and Networking Setup**: Create and configure secure virtual networks and subnets.
- **S3 Bucket Storage**: Provision cloud storage for application data or backups.
- **Security Group Management**: Define and control access to deployed resources.
- **Modular Infrastructure**: Reusable Terraform modules for EC2, S3, VPC, and more.

## **Conclusion**

This project provides a practical solution for **automating cloud infrastructure management** using **Terraform**. It not only streamlines the deployment process but also equips **IT staff** with the skills and tools needed to manage and scale cloud resources effectively. Through modular configurations and training materials, the project empowers businesses to manage their cloud infrastructure more efficiently.

**Troubleshooting** 

EC2 Instance:
sudo cat /var/log/cloud-init-output.log
sudo systemctl status nginx
sudo systemctl status cron
