#!/usr/bin/python

from messenger import Messenger
from os        import getpid
from sys       import argv

freeValue = argv[1]
messenger = Messenger('http://127.0.0.1:24192/p/dt-py-' + str(getpid()).zfill(5))
received = []
latestProposedTimePeriod = 0

while True:
  currMessage = messenger.getNextMessage()
  if currMessage['timePeriod'] <= latestProposedTimePeriod: continue
  for prevMessage in received:
    if currMessage['timePeriod'] != prevMessage['timePeriod']: continue
    if currMessage['by'] == prevMessage['by']: continue

    proposedValue = freeValue

    currLATP = currMessage.get('lastAcceptedTimePeriod', -1)
    prevLATP = prevMessage.get('lastAcceptedTimePeriod', -1)

    if currLATP > 0:
      proposedValue = currMessage['lastAcceptedValue']

    if prevLATP > 0 and prevLATP > currLATP:
      proposedValue = currMessage['lastAcceptedValue']

    messenger.postMessage({'type':'proposed','timePeriod':currMessage['timePeriod'], 'value':proposedValue})
    break

  received.append(currMessage)
