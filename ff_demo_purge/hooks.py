"""Installing the module is the whole point, so it clears up on the way in."""
import logging

_logger = logging.getLogger(__name__)


def post_init_hook(env):
    """Remove the demo data as soon as this module is installed."""
    removed = env['ff.demo.purge']._ff_purge()
    if removed:
        _logger.warning('Field Force demo data removed on install: %s', removed)
    else:
        _logger.info('Field Force demo purge: nothing to remove.')
