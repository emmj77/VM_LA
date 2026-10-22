# phone-tunnel

## what it is
A route, not a recipe. It brings the phone up to the bridge and proves it with the machine.
The route is the PLAN of skill.yaml: four steps, each opening its own set of tools.

## the three tools
- tunnel_status : wg0 state, address, UDP port, pairs and latest handshake
- tunnel_up : raise wg0, writing the profile when it is lost
- tunnel_down : lower it

## the law
- a step closes on a FACT, never on the word of tunnel_up: the return must carry every literal of close
- the engine closes it (skl_step_close) at the call itself; the model never declares a step done
- a step that cannot pass says what is missing: the literal the return does not carry

## the four steps
401 read what stands -> 402 raise wg0 -> 403 prove it by the fact -> 404 report four lines

## what it never does
- lay wg0 down unasked: it belongs to the machine, not to the route
- open the bridge on the network: it listens on 127.0.0.1, the tunnel is what brings the phone
- raise the tunnel and call it proven on the word of the tool
