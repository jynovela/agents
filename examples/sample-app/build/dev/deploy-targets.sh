DEPLOY_local='mkdir -p deploy/local && cp dist/itemctl.pyz deploy/local/'
ROLLBACK_local=''
DEPLOY_staging='mkdir -p deploy/staging && if [ -f deploy/staging/itemctl.pyz ]; then cp deploy/staging/itemctl.pyz deploy/staging/itemctl.pyz.prev; fi && cp dist/itemctl.pyz deploy/staging/'
ROLLBACK_staging='mv deploy/staging/itemctl.pyz.prev deploy/staging/itemctl.pyz'
