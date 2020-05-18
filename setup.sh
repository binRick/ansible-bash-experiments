
export PATH="$(pwd)/bin:$PATH"
echo -e "export PATH=$PATH"


cd $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
_VD="$(pwd)/.venv"
[[ ! -d "$_VD" ]] && python3 -m venv $_VD
source $_VD/bin/activate

pip install pip --upgrade
pip install 'j2cli[yaml]'

command -v j2 
  
