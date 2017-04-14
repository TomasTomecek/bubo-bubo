dnf install -y git ansible
git clone https://github.com/TomasTomecek/bubo-bubo
cd bubo-bubo
ansible-playbook ./playbook.yaml
